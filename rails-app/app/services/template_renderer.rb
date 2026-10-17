class TemplateRenderer
  MissingVariableError = Class.new(StandardError)

  Result = Struct.new(:body, :mentioned_jids)

  MENTION_PATTERN = /@\{\{([^{}]+)\}\}/

  MONTHS = %w[Janeiro Fevereiro Março Abril Maio Junho Julho Agosto Setembro Outubro Novembro Dezembro].freeze

  class << self
    def call(template, variables, whatsapp_group: nil, now: Time.current)
      variables = variables.to_h.stringify_keys
      mentioned_jids = []

      body = template.body.gsub(MENTION_PATTERN) do
        key = Regexp.last_match(1).strip
        participant = resolve_mention(key, whatsapp_group)

        if participant
          mentioned_jids << participant.jid
          "@#{participant.phone_number}"
        else
          Rails.logger.warn("TemplateRenderer: menção não resolvida para \"#{key}\" (template ##{template.id.inspect})")
          "@#{key}"
        end
      end

      body = body.gsub(Template::VARIABLE_PATTERN) do
        key = Regexp.last_match(1)
        variables.fetch(key) do
          builtin(key, now, whatsapp_group, mentioned_jids) || raise(MissingVariableError, "Variável não preenchida: #{key}")
        end
      end

      Result.new(body, mentioned_jids.uniq)
    end

    private

    def builtin(key, now, whatsapp_group, mentioned_jids)
      case key
      when "data" then now.strftime("%d/%m")
      when "mes" then MONTHS[now.month - 1]
      when "mes_num" then now.strftime("%m")
      when "mes_anterior" then MONTHS[now.prev_month.month - 1]
      when "lista_mensais" then numbered(participants(whatsapp_group, "mensal").map(&:label))
      when "lista_espera" then numbered(participants(whatsapp_group, "espera").map(&:label))
      when "mencoes_mensais"
        mensais = participants(whatsapp_group, "mensal")
        mentioned_jids.concat(mensais.map(&:jid))
        numbered(mensais.map { |participant| "@#{participant.phone_number}" })
      end
    end

    def participants(whatsapp_group, role)
      return [] unless whatsapp_group

      whatsapp_group.group_participants.where(role: role).sort_by { |participant| participant.label.to_s.downcase }
    end

    def numbered(items)
      items.each_with_index.map { |item, index| "#{index + 1}. #{item}" }.join("\n")
    end

    def resolve_mention(key, whatsapp_group)
      return nil unless whatsapp_group

      if key.match?(/\A[\d\s()+-]+\z/)
        digits = key.gsub(/\D/, "")
        whatsapp_group.group_participants.find_by(phone_number: digits)
      else
        matches = whatsapp_group.group_participants.where("LOWER(name) = ?", key.downcase).to_a
        matches.size == 1 ? matches.first : nil
      end
    end
  end
end
