# Regra de grupo "Lista de presença" (ver GroupRule). Cada envio do template configurado na
# regra abre uma rodada; reações/respostas nela viram Attendance::Response. Tudo é configurável
# por grupo em rule.settings (ver DEFAULTS). Grupos sem a regra não passam por nada daqui.
module Attendance
  DEFAULTS = {
    "categories" => [
      { "key" => "mensal", "name" => "Mensal", "fixed" => true },
      { "key" => "avulso", "name" => "Avulso", "fixed" => false },
      { "key" => "espera", "name" => "Espera", "fixed" => false }
    ],
    "confirm_emojis" => "✅ ✔ ☑ 👍",
    "decline_emojis" => "❌ ✖ ❎ 👎",
    "accept_replies" => true,
    "list_style" => "numbered",
    "confirmed_mark" => "✅",
    "declined_mark" => "❌",
    "pending_mark" => "",
    "empty_text" => "1.",
    "list_command" => "!lista",
    "list_reply_template_id" => nil
  }.freeze

  # Resposta ao comando quando a regra não aponta um template.
  DEFAULT_LIST_REPLY = "*Lista de presença*\n\n{{presenca}}\n\n*Avulsos*\n{{confirmados}}".freeze

  LIST_STYLES = { "numbered" => "Numerada (1. 2. 3.)", "bullet" => "Marcador •", "dash" => "Traço -", "plain" => "Sem marcador" }.freeze

  # {{nome}} ou {{nome:categoria}}. Sem categoria: as fixas (exceto confirmados, que pega as não fixas).
  VARIABLE_NAMES = %w[lista mencoes presenca confirmados pendentes].freeze
  ROUND_VARIABLES = %w[presenca confirmados pendentes].freeze

  class << self
    def settings(rule)
      DEFAULTS.merge(rule.settings.except("template_id"))
    end

    def categories(rule)
      settings(rule)["categories"]
    end

    def fixed_keys(rule)
      categories(rule).select { |category| category["fixed"] }.map { |category| category["key"] }
    end

    def provides_variable?(rule, key)
      name, category = key.split(":", 2)
      VARIABLE_NAMES.include?(name) && (category.nil? || categories(rule).any? { |c| c["key"] == category })
    end

    # Converte o formulário da regra em settings (os nomes dos campos são as chaves).
    def settings_from(params)
      categories = params.fetch(:categories, {}).values.filter_map do |category|
        name = category[:name].to_s.strip
        next if name.empty?

        key = category[:key].presence || name.parameterize(separator: "_").presence || "categoria_#{SecureRandom.hex(2)}"
        { "key" => key, "name" => name, "fixed" => category[:fixed] == "1" }
      end

      {
        "template_id" => params[:template_id].presence,
        "categories" => categories.uniq { |category| category["key"] },
        "confirm_emojis" => params[:confirm_emojis].to_s.strip,
        "decline_emojis" => params[:decline_emojis].to_s.strip,
        "accept_replies" => params[:accept_replies] == "1",
        "list_style" => LIST_STYLES.key?(params[:list_style]) ? params[:list_style] : "numbered",
        "confirmed_mark" => params[:confirmed_mark].to_s.strip,
        "declined_mark" => params[:declined_mark].to_s.strip,
        "pending_mark" => params[:pending_mark].to_s.strip,
        "empty_text" => params[:empty_text].to_s,
        "list_command" => params[:list_command].to_s.strip.downcase,
        "list_reply_template_id" => params[:list_reply_template_id].presence
      }.select { |key, _| params.key?(key) } # campo ausente no formulário mantém o valor salvo
    end

    def current_round(rule)
      MessageLog.joins(:schedule)
        .where(status: "sent", group_jid: rule.whatsapp_group.jid, schedules: { template_id: rule.template_id.to_i })
        .where.not(wa_message_id: nil)
        .order(sent_at: :desc).first
    end

    # A rodada da mensagem: ela mesma se for a lista, ou a que ela acompanha.
    def round_for(rule, message_log)
      return message_log if message_log.schedule&.template_id == rule.template_id.to_i

      MessageLog.find_by(id: message_log.round_id) if message_log.round_id
    end

    # Mensagens que mostram a rodada (lista atualizada, lembrete) ficam ligadas a ela,
    # para que reações nelas também contem.
    def after_send(rule, message_log)
      template = message_log.schedule&.template
      return unless template && template.id != rule.template_id.to_i
      return unless template.variable_names.any? { |key| ROUND_VARIABLES.include?(key.split(":").first) }

      message_log.update!(round_id: current_round(rule)&.id)
    end

    def handle_event(rule, event)
      return reply_with_list(rule) if event[:kind] == "command" && command?(rule, event[:text])
      return if event[:kind] == "reply" && !settings(rule)["accept_replies"]

      message_log = MessageLog.find_by(wa_message_id: event[:message_id], group_jid: rule.whatsapp_group.jid)
      round = message_log && round_for(rule, message_log)
      round && record(rule, round, event)
    end

    def render_variable(rule, key, mentioned_jids)
      return unless provides_variable?(rule, key)

      name, category = key.split(":", 2)
      config = settings(rule)
      group = rule.whatsapp_group
      keys = category ? [ category ] : fixed_keys(rule)

      case name
      when "lista" then list(config, members(group, keys).map(&:label))
      when "mencoes"
        people = members(group, keys)
        mentioned_jids.concat(people.map(&:jid))
        list(config, people.map { |participant| "@#{participant.phone_number}" })
      when "presenca"
        statuses = statuses(rule)
        list(config, members(group, keys).map { |participant| [ participant.label, mark(config, statuses[participant.id]) ].compact_blank.join(" ") })
      when "confirmados"
        confirmed_ids = statuses(rule).select { |_, status| status == "confirmed" }.keys
        people = group.group_participants.where(id: confirmed_ids).to_a
        people = category ? people.select { |p| p.role == category } : people.reject { |p| fixed_keys(rule).include?(p.role) }
        list(config, sorted(people).map(&:label))
      when "pendentes"
        statuses = statuses(rule)
        people = members(group, keys).reject { |participant| statuses.key?(participant.id) }
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

    def command?(rule, text)
      command = settings(rule)["list_command"].to_s
      command.present? && text.to_s.strip.downcase.split.first == command
    end

    # Responde ao comando com a lista da rodada atual. A resposta fica ligada à rodada,
    # então reações nela também contam.
    def reply_with_list(rule)
      round = current_round(rule)
      return unless round

      template = ::Template.find_by(id: settings(rule)["list_reply_template_id"]) || ::Template.new(body: DEFAULT_LIST_REPLY)
      result = TemplateRenderer.call(template, template.default_variables.to_h, whatsapp_group: rule.whatsapp_group)
      message_log = MessageLog.create!(group_jid: rule.whatsapp_group.jid, rendered_body: result.body, status: "pending", round_id: round.id)
      DeliverMessageJob.perform_async(message_log.id, result.mentioned_jids)
    end

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

      participant = group.group_participants.find_or_create_by!(jid: event[:participant_jid]) do |new_participant|
        new_participant.name = event[:push_name].presence
        new_participant.phone_number = event[:participant_jid].split("@").first.split(":").first
      end

      Response.find_or_initialize_by(message_log: round, group_participant: participant).update!(status: status)
    end

    def status_for(config, text)
      if config["confirm_emojis"].split.any? { |emoji| text.start_with?(emoji) } then "confirmed"
      elsif config["decline_emojis"].split.any? { |emoji| text.start_with?(emoji) } then "declined"
      end
    end

    def members(group, keys)
      sorted(group.group_participants.where(role: keys))
    end

    def sorted(participants)
      participants.sort_by { |participant| participant.label.to_s.downcase }
    end

    def list(config, items)
      return config["empty_text"] if items.empty?

      items.each_with_index.map do |item, index|
        prefix = { "numbered" => "#{index + 1}. ", "bullet" => "• ", "dash" => "- " }.fetch(config["list_style"], "")
        "#{prefix}#{item}"
      end.join("\n")
    end
  end
end
