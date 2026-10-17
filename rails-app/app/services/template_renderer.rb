class TemplateRenderer
  MissingVariableError = Class.new(StandardError)

  Result = Struct.new(:body, :mentioned_jids)

  MENTION_PATTERN = /@\{\{([^{}]+)\}\}/

  # @{{todos}} menciona todos os participantes sincronizados sem listar os números no texto
  # (a notificação vai pelas mentions), como o "@todos" do WhatsApp.
  MENTION_ALL_KEYS = %w[todos all].freeze

  MONTHS = %w[Janeiro Fevereiro Março Abril Maio Junho Julho Agosto Setembro Outubro Novembro Dezembro].freeze

  class << self
    # Prioridade dos valores: variables (ex.: JSON do agendamento) > variáveis do grupo >
    # padrões do template > automáticas e de regras de grupo.
    def call(template, variables, whatsapp_group: nil, now: Time.current)
      variables = template.default_variables.to_h
        .merge(whatsapp_group&.variables || {})
        .merge(variables.to_h.stringify_keys)
      mentioned_jids = []

      body = template.body.gsub(MENTION_PATTERN) do
        key = Regexp.last_match(1).strip

        if whatsapp_group && MENTION_ALL_KEYS.include?(key.downcase)
          mentioned_jids.concat(whatsapp_group.group_participants.pluck(:jid))
          next "@#{key}"
        end

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
      else whatsapp_group&.render_rule_variable(key, mentioned_jids)
      end
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
