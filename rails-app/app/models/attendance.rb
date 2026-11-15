# Regra de grupo "Lista de presença" (ver GroupRule). Cada mensagem enviada por um passo de
# fluxo marcado "abre rodada" abre uma rodada; reações/respostas nela viram Attendance::Response.
# As listas acompanhadas (tracked_lists) são as cobradas em {{presenca}} e {{pendentes}}.
# Listas copiadas, editadas e coladas no grupo também contam (ver read_list).
module Attendance
  DEFAULTS = {
    "tracked_lists" => [],
    "confirm_emojis" => "✅ ✔ ☑ 👍",
    "decline_emojis" => "❌ ✖ ❎ 👎",
    "accept_replies" => true,
    "confirmed_mark" => "✅",
    "declined_mark" => "❌",
    "pending_mark" => "",
    "read_lists" => true,
    "extras_section" => "Avulsos"
  }.freeze

  # "3. Carla ✅", " 12) Leonardo ❌"
  LIST_LINE = /\A\s*\d+\s*[.)-]\s*(.*)\z/

  # {{nome}} ou {{nome:lista}}. Sem lista: as acompanhadas (exceto confirmados, que pega quem
  # está fora delas). {{lista}}/{{mencoes}} com lista são do próprio grupo (WhatsappGroup).
  VARIABLE_NAMES = %w[lista mencoes presenca confirmados pendentes].freeze
  ROUND_VARIABLES = %w[presenca confirmados pendentes].freeze

  class << self
    def settings(rule)
      DEFAULTS.merge(rule.settings)
    end

    def tracked_keys(rule)
      settings(rule)["tracked_lists"]
    end

    def provides_variable?(rule, key)
      name, list_key = key.split(":", 2)
      return false unless VARIABLE_NAMES.include?(name)
      return list_key.nil? if WhatsappGroup::LIST_VARIABLES.include?(name)

      list_key.nil? || rule.whatsapp_group.member_lists.any? { |list| list.key == list_key }
    end

    # Converte o formulário da regra em settings (os nomes dos campos são as chaves).
    def settings_from(params)
      {
        "tracked_lists" => Array(params[:tracked_lists]).compact_blank,
        "confirm_emojis" => params[:confirm_emojis].to_s.strip,
        "decline_emojis" => params[:decline_emojis].to_s.strip,
        "accept_replies" => params[:accept_replies] == "1",
        "confirmed_mark" => params[:confirmed_mark].to_s.strip,
        "declined_mark" => params[:declined_mark].to_s.strip,
        "pending_mark" => params[:pending_mark].to_s.strip,
        "read_lists" => params[:read_lists] == "1",
        "extras_section" => params[:extras_section].to_s.strip
      }.select { |key, _| params.key?(key) } # campo ausente no formulário mantém o valor salvo
    end

    def current_round(rule)
      MessageLog.where(status: "sent", group_jid: rule.whatsapp_group.jid, opens_round: true)
        .where.not(wa_message_id: nil)
        .order(sent_at: :desc).first
    end

    # A rodada da mensagem: ela mesma se abriu a rodada, ou a que ela acompanha.
    def round_for(message_log)
      message_log.opens_round ? message_log : MessageLog.find_by(id: message_log.round_id)
    end

    def before_message(_rule, _step, _now) = nil

    # Mensagens que mostram a rodada (lista atualizada, lembrete) ficam ligadas a ela,
    # para que reações nelas também contem. Chamado antes de salvar cada mensagem do grupo.
    def prepare_message(rule, message_log, template)
      return if message_log.opens_round
      return unless template.variable_names.any? { |key| ROUND_VARIABLES.include?(key.split(":").first) }

      message_log.round_id = current_round(rule)&.id
    end

    def handle_event(rule, event)
      return read_list(rule, event) if event[:kind] == "list"
      return unless %w[reaction reply].include?(event[:kind])
      return if event[:kind] == "reply" && !settings(rule)["accept_replies"]

      message_log = MessageLog.find_by(wa_message_id: event[:message_id], group_jid: rule.whatsapp_group.jid)
      round = message_log && round_for(message_log)
      round && record(rule, round, event)
    end

    def render_variable(rule, key, mentioned_jids)
      return unless provides_variable?(rule, key)

      name, list_key = key.split(":", 2)
      config = settings(rule)
      group = rule.whatsapp_group
      keys = list_key ? [ list_key ] : tracked_keys(rule)

      case name
      when "lista", "mencoes" then group.render_list_variable(name, keys, mentioned_jids)
      when "presenca"
        statuses = statuses(rule)
        group.format_list(group.members_of(keys).map { |participant| [ participant.label, mark(config, statuses[participant.id]) ].compact_blank.join(" ") })
      when "confirmados"
        confirmed_ids = statuses(rule).select { |_, status| status == "confirmed" }.keys
        people = group.group_participants.where(id: confirmed_ids).includes(:member_lists).to_a
        in_lists = ->(participant, list_keys) { participant.member_lists.any? { |list| list_keys.include?(list.key) } }
        people = list_key ? people.select { |p| in_lists.(p, keys) } : people.reject { |p| in_lists.(p, tracked_keys(rule)) }
        guests = list_key ? [] : Response.where(message_log: current_round(rule), group_participant_id: nil, status: "confirmed").pluck(:guest_name)
        group.format_list((people.map(&:label) + guests).sort_by { |label| label.to_s.downcase })
      when "pendentes"
        statuses = statuses(rule)
        people = group.members_of(keys).reject { |participant| statuses.key?(participant.id) }
        mentioned_jids.concat(people.map(&:jid))
        people.map { |participant| "@#{participant.phone_number}" }.join(" ")
      end
    end

    # { group_participant_id => "confirmed"/"declined" } da rodada atual.
    def statuses(rule)
      round = current_round(rule)
      round ? Response.where(message_log: round).where.not(group_participant_id: nil).pluck(:group_participant_id, :status).to_h : {}
    end

    # Convidados (só nome) da rodada atual: { "Pedro" => "confirmed" }.
    def guest_statuses(rule)
      Response.where(message_log: current_round(rule), group_participant_id: nil).pluck(:guest_name, :status).to_h
    end

    # Nomes de listas coladas que ainda não batem com nenhum membro.
    def unmatched_names(rule)
      round = current_round(rule)
      return [] unless round

      people = GroupParticipant.where(whatsapp_group_id: rule.whatsapp_group_id).to_a
      round.unmatched_names.reject { |name| rule.whatsapp_group.participant_named(name, people: people) }
    end

    def mark(config, status)
      { "confirmed" => config["confirmed_mark"], "declined" => config["declined_mark"] }.fetch(status, config["pending_mark"])
    end

    private

    def record(rule, round, event)
      group = rule.whatsapp_group
      text = event[:text].to_s.strip

      # Reação removida: apaga a resposta.
      if event[:kind] == "reaction" && text.empty?
        participant = group.group_participants.find_by(jid: event[:participant_jid])
        if participant && Response.where(message_log: round, group_participant: participant).destroy_all.any?
          AnalyticsEvent.track(:presenca_desfeita, rodada_id: round.id, whatsapp_group_id: group.id, participante_id: participant.id)
        end
        return
      end

      status = status_for(settings(rule), text)
      return unless status

      participant = group.participant_for!(event[:participant_jid], event[:push_name])
      response = Response.find_or_initialize_by(message_log: round, group_participant: participant)
      track_response(rule, response, event[:kind] == "reaction" ? "reacao" : "resposta") { response.update!(status: status) }
    end

    # presenca_registrada (tracking-plan), só quando a resposta é criada ou muda: sem nome; convidado só como booleano.
    def track_response(rule, response, origem)
      existed = response.persisted?
      yield
      return unless response.saved_change_to_status?

      participant = response.group_participant
      AnalyticsEvent.track(:presenca_registrada, rodada_id: response.message_log_id, whatsapp_group_id: rule.whatsapp_group_id,
                           participante_id: participant&.id, convidado: participant.nil?,
                           membro_cobrado: participant.present? && participant.member_lists.where(key: tracked_keys(rule)).exists?,
                           status: response.status, origem: origem, alterou_resposta: existed)
    end

    # Lista da rodada copiada, editada e colada no grupo. Cada linha numerada é uma pessoa;
    # as linhas antes do primeiro título são as listas cobradas, e na seção de avulsos
    # (extras_section) estar na lista já é confirmar. Como cópias podem estar desatualizadas,
    # uma colagem preenche quem ainda não respondeu, mas só a linha da própria pessoa muda uma
    # resposta já registrada. Nomes sem membro correspondente viram convidados (nos avulsos)
    # ou ficam em unmatched_names (nas listas cobradas) para o admin associar.
    def read_list(rule, event)
      config = settings(rule)
      round = current_round(rule)
      return unless config["read_lists"] && round

      lines = event[:text].to_s.lines.map(&:strip)
      header_index = lines.index(&:present?)
      return unless header_index && round_headers(round).include?(WhatsappGroup.normalize_name(lines[header_index]))

      group = rule.whatsapp_group
      people = GroupParticipant.where(whatsapp_group_id: group.id).to_a
      sender = people.find { |participant| participant.jid == event[:participant_jid] }
      responses = Response.where(message_log: round).index_by { |response| response.group_participant_id || response.guest_name }
      extras = WhatsappGroup.normalize_name(config["extras_section"])
      in_extras = false
      unmatched = []

      lines.drop(header_index + 1).each do |line|
        next if line.empty?

        content = line[LIST_LINE, 1]
        unless content # título de seção
          in_extras = extras.present? && WhatsappGroup.normalize_name(line) == extras
          next
        end

        name = content.gsub(/[^\p{L}\p{N}\s.'@-]/, "").squish
        next if name.empty?

        participant = group.participant_named(name, people: people)
        status = status_for(config, content, anywhere: true) || ("confirmed" if in_extras)
        if !participant && !in_extras
          unmatched << name
        elsif status
          key = participant&.id || name
          next if responses[key] && (participant.nil? || participant != sender)

          responses[key] = Response.find_or_initialize_by(message_log: round, group_participant: participant, guest_name: (name unless participant))
          track_response(rule, responses[key], "lista") { responses[key].update!(status: status) }
        end
      end

      round.update!(unmatched_names: (round.unmatched_names + unmatched).uniq) if unmatched.any?
    end

    # Primeira linha das mensagens da rodada (a que abriu e as ligadas a ela, como o !lista).
    def round_headers(round)
      MessageLog.where(id: round.id).or(MessageLog.where(round_id: round.id)).pluck(:rendered_body)
        .filter_map { |body| WhatsappGroup.normalize_name(body.to_s.lines.find(&:present?)).presence }.uniq
    end

    def status_for(config, text, anywhere: false)
      found = ->(emoji) { anywhere ? text.include?(emoji) : text.start_with?(emoji) }
      if config["confirm_emojis"].split.any?(&found) then "confirmed"
      elsif config["decline_emojis"].split.any?(&found) then "declined"
      end
    end
  end
end
