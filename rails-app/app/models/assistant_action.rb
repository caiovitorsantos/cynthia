# Ação que a Cynth.ia propôs no chat (criar template, criar fluxo, definir variável). Só roda
# quando o usuário confirma, passando pelas mesmas validações do painel.
class AssistantAction < ApplicationRecord
  KINDS = %w[create_template create_flow set_variable].freeze
  CHANNELS = %w[panel group].freeze
  YES = %w[sim s yes y si sí ok confirmo confirma confirmar 👍 ✅].freeze
  STATUSES = %w[pending done failed cancelled].freeze
  NOTE_PREFIX = "[painel]".freeze
  GROUP_EXPIRY = 1.hour # T5: "sim" depois disso não executa (admin pode ter sido rebaixado)

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :channel, inclusion: { in: CHANNELS }

  belongs_to :message_log, optional: true

  scope :panel, -> { where(channel: "panel") }
  scope :unreported, -> { panel.where(reported: false).where.not(status: "pending") }

  # Admin respondeu "sim" citando a mensagem da Cynth.ia com propostas: executa e responde no grupo.
  # Devolve true se a resposta era para ela (para não cair em outras regras).
  def self.confirm_from_group_reply(group, event)
    log = MessageLog.find_by(wa_message_id: event[:message_id], group_jid: group.jid)
    actions = log ? where(message_log: log, status: "pending").order(:id).to_a : []
    return false if actions.empty?

    if log.created_at < GROUP_EXPIRY.ago
      actions.each(&:cancel!)
      return true
    end

    sender = group.group_participants.find_by(jid: event[:participant_jid])
    word = event[:text].to_s.strip.downcase.split.first.to_s.delete(".!,")
    return true unless sender&.admin? && YES.include?(word)

    actions.each(&:confirm!)
    I18n.with_locale(group.locale) do
      body = actions.map { |action| I18n.t("assistant.group.result.#{action.status}", what: action.summary, result: action.result) }.join("\n")
      reply = MessageLog.create!(group_jid: group.jid, rendered_body: body, status: "pending")
      DeliverMessageJob.perform_async(reply.id, [])
    end
    true
  end

  def group
    WhatsappGroup.find_by(id: payload["group_id"])
  end

  def pending? = status == "pending"

  def confirm!
    return unless pending?

    record = send("run_#{kind}")
    update!(status: "done", result: record)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ArgumentError => e
    update!(status: "failed", result: e.message)
  end

  # Uma linha que diz o que é ("template \"Lembrete\"").
  def summary
    I18n.t("assistant.group.summary.#{kind}", name: payload["name"])
  end

  # Prévia completa para o grupo: tudo o que será salvo, já que a confirmação é por texto.
  def preview
    lines = [ "*#{I18n.t("assistant.group.proposal", id: id)}* #{summary}" ]
    case kind
    when "create_template" then lines << payload["body"].to_s
    when "set_variable" then lines << "{{#{payload["name"]}}} = #{payload["value"]}"
    when "create_flow"
      lines << payload.slice("trigger", "command", "cron_expression", "run_at", "timezone").compact_blank.map { |field, value| "#{field}: #{value}" }.join(" · ")
      Array(payload["steps"]).each_with_index do |step, index|
        lines << "#{index + 1}. #{step.map { |field, value| "#{field}: #{value}" }.join(", ")}"
      end
    end
    lines.join("\n")
  end

  def cancel!
    update!(status: "cancelled") if pending?
  end

  # Como a Cynth.ia fica sabendo do desfecho no turno seguinte.
  def note
    "#{NOTE_PREFIX} #{kind} ##{id}: #{status}#{" (#{result})" if result.present?}"
  end

  private

  def run_create_template
    template = group!.templates.create!(name: payload["name"], body: payload["body"])
    "template ##{template.id}"
  end

  # Passos vêm com template_name (o template pode ter sido criado por uma ação confirmada antes).
  def run_create_flow
    group = group!
    steps = Array(payload["steps"]).map do |raw|
      step = raw.slice("type", "list_key", "name", "value")
      %w[opens_round opens_billing].each { |flag| step[flag] = raw[flag] ? "1" : "0" if raw.key?(flag) }
      if raw["template_name"].present?
        template = group.templates.find_by(name: raw["template_name"]) || raise(ArgumentError, "template \"#{raw["template_name"]}\" não existe")
        step["template_id"] = template.id.to_s
      end
      step
    end
    flow = group.flows.create!(name: payload["name"], trigger: payload["trigger"], command: payload["command"],
                               cron_expression: payload["cron_expression"], run_at: payload["run_at"],
                               timezone: payload["timezone"].presence || "America/Sao_Paulo", steps: steps)
    "fluxo ##{flow.id}"
  end

  def run_set_variable
    group = group!
    key = Template.key_for(payload["name"])
    group.update!(variables: group.variables.merge(key => payload["value"].to_s))
    "{{#{key}}}"
  end

  def group!
    group || raise(ActiveRecord::RecordNotFound, "grupo ##{payload["group_id"]} não existe")
  end
end
