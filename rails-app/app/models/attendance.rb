# Recurso de grupo "Lista de presença" (ver GroupRule). Cada mensagem enviada por um passo de
# fluxo marcado "abre rodada" abre uma rodada; reações/respostas nela viram Attendance::Response.
# As listas acompanhadas (tracked_lists) são as cobradas em {{presenca}} e {{pendentes}}.
module Attendance
  DEFAULTS = {
    "tracked_lists" => [],
    "confirm_emojis" => "✅ ✔ ☑ 👍",
    "decline_emojis" => "❌ ✖ ❎ 👎",
    "accept_replies" => true,
    "confirmed_mark" => "✅",
    "declined_mark" => "❌",
    "pending_mark" => ""
  }.freeze

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

    # Converte o formulário do recurso em settings (os nomes dos campos são as chaves).
    def settings_from(params)
      {
        "tracked_lists" => Array(params[:tracked_lists]).compact_blank,
        "confirm_emojis" => params[:confirm_emojis].to_s.strip,
        "decline_emojis" => params[:decline_emojis].to_s.strip,
        "accept_replies" => params[:accept_replies] == "1",
        "confirmed_mark" => params[:confirmed_mark].to_s.strip,
        "declined_mark" => params[:declined_mark].to_s.strip,
        "pending_mark" => params[:pending_mark].to_s.strip
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

    # Mensagens que mostram a rodada (lista atualizada, lembrete) ficam ligadas a ela,
    # para que reações nelas também contem. Chamado antes de salvar cada mensagem do grupo.
    def prepare_message(rule, message_log, template)
      return if message_log.opens_round
      return unless template.variable_names.any? { |key| ROUND_VARIABLES.include?(key.split(":").first) }

      message_log.round_id = current_round(rule)&.id
    end

    def handle_event(rule, event)
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
        group.format_list(people.sort_by { |participant| participant.label.to_s.downcase }.map(&:label))
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
      round ? Response.where(message_log: round).pluck(:group_participant_id, :status).to_h : {}
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
        Response.where(message_log: round, group_participant: participant).destroy_all if participant
        return
      end

      status = status_for(settings(rule), text)
      return unless status

      participant = group.participant_for!(event[:participant_jid], event[:push_name])
      Response.find_or_initialize_by(message_log: round, group_participant: participant).update!(status: status)
    end

    def status_for(config, text)
      if config["confirm_emojis"].split.any? { |emoji| text.start_with?(emoji) } then "confirmed"
      elsif config["decline_emojis"].split.any? { |emoji| text.start_with?(emoji) } then "declined"
      end
    end
  end
end
