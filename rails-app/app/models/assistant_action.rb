# Ação que a Cynth.ia propôs no chat (criar template, criar fluxo, definir variável). Só roda
# quando o usuário confirma, passando pelas mesmas validações do painel.
class AssistantAction < ApplicationRecord
  KINDS = %w[create_template create_flow set_variable].freeze
  STATUSES = %w[pending done failed cancelled].freeze
  NOTE_PREFIX = "[painel]".freeze

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }

  scope :unreported, -> { where(reported: false).where.not(status: "pending") }

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
    group.update!(variables: group.variables.merge(payload["name"].to_s.parameterize(separator: "_") => payload["value"].to_s))
    "{{#{payload["name"]}}}"
  end

  def group!
    group || raise(ActiveRecord::RecordNotFound, "grupo ##{payload["group_id"]} não existe")
  end
end
