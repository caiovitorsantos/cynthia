# Automação de um grupo: um gatilho (horário ou comando "!algo" no grupo) e passos executados
# em ordem. Fluxo de horário é a "rotina". Os passos são os componentes de STEPS; os que agem
# sobre "quem mandou" só fazem sentido em fluxos de comando.
class Flow < ApplicationRecord
  TRIGGERS = { "schedule" => "Horário (rotina)", "command" => "Comando no grupo" }.freeze

  STEPS = {
    "send_message" => { label: "Enviar template", fields: %w[template_id opens_round] },
    "add_to_list" => { label: "Pôr quem mandou o comando numa lista", fields: %w[list_key], sender: true },
    "remove_from_list" => { label: "Tirar quem mandou o comando de uma lista", fields: %w[list_key], sender: true },
    "clear_list" => { label: "Esvaziar lista", fields: %w[list_key] },
    "set_variable" => { label: "Definir variável do grupo", fields: %w[name value] }
  }.freeze

  # Disponíveis nos templates e valores de passos de um fluxo de comando.
  COMMAND_VARIABLES = %w[remetente argumento].freeze

  belongs_to :whatsapp_group
  has_many :message_logs, dependent: :nullify

  normalizes :command, with: ->(value) { value.strip.downcase.presence }

  validates :name, presence: true
  validates :trigger, inclusion: { in: TRIGGERS.keys }
  validates :command, presence: true, format: { with: /\A!\S+\z/, message: "deve ser uma palavra começando com !, ex: !lista" }, if: :command?
  validate :schedule_is_valid, if: :schedule?
  validate :steps_are_valid

  before_validation :clear_other_trigger_fields
  before_save :plan_next_run, if: -> { will_save_change_to_trigger? || will_save_change_to_cron_expression? || will_save_change_to_run_at? || will_save_change_to_timezone? }

  scope :active, -> { where(active: true) }

  # Linhas do formulário → passos, só com os campos do tipo escolhido. Linha sem tipo é descartada.
  def self.steps_from(rows)
    rows.to_h.values.filter_map do |row|
      step = STEPS[row[:type]]
      next unless step

      values = step[:fields].index_with { |field| row[field].to_s.strip }
      values["name"] = values["name"].parameterize(separator: "_") if values.key?("name")
      { "type" => row[:type] }.merge(values)
    end
  end

  def self.for_command(text)
    active.where(trigger: "command", command: text.to_s.strip.downcase.split.first)
  end

  def schedule? = trigger == "schedule"
  def command? = trigger == "command"

  def template_ids
    steps.filter_map { |step| step["template_id"].to_i if step["type"] == "send_message" }
  end

  # context (fluxo de comando): "sender_jid", "push_name" e "text" da mensagem do comando.
  def run!(context = {})
    sender = whatsapp_group.participant_for!(context["sender_jid"], context["push_name"]) if context["sender_jid"].present?
    variables = sender ? { "remetente" => sender.label, "argumento" => context["text"].to_s.strip.split(" ", 2)[1].to_s } : {}
    delay = 0

    steps.each do |step|
      next if STEPS[step["type"]][:sender] && !sender # comando do próprio número conectado chega sem remetente
      list = whatsapp_group.member_lists.find_by!(key: step["list_key"]) if step["list_key"].present?

      case step["type"]
      when "send_message"
        send_template(whatsapp_group.templates.find(step["template_id"]), variables, opens_round: step["opens_round"] == "1", delay: delay)
        # ponytail: espaça os envios pela janela do SendGuard; fila por grupo se ficar lento.
        delay += SendGuard::THROTTLE_WINDOW + 1
      when "add_to_list" then list.group_participants << sender unless list.group_participants.include?(sender)
      when "remove_from_list" then list.group_participants.delete(sender)
      when "clear_list" then list.group_participants.clear
      when "set_variable"
        value = TemplateRenderer.call(Template.new(body: step["value"]), variables, whatsapp_group: whatsapp_group).body
        whatsapp_group.update!(variables: whatsapp_group.variables.merge(step["name"] => value))
      end
    end
  end

  private

  def clear_other_trigger_fields
    if command?
      self.cron_expression = self.run_at = nil
    else
      self.command = nil
    end
  end

  def plan_next_run
    self.last_run_at = nil if will_save_change_to_run_at? # envio único com nova data pode rodar de novo
    self.next_run_at = schedule? ? ScheduleCalculator.next_run(self) : nil
  end

  def send_template(template, variables, opens_round:, delay:)
    result = TemplateRenderer.call(template, variables, whatsapp_group: whatsapp_group, now: Time.current.in_time_zone(timezone))
    message_log = message_logs.new(group_jid: whatsapp_group.jid, rendered_body: result.body, status: "pending", opens_round: opens_round)
    whatsapp_group.group_rules.each { |rule| rule.handler.prepare_message(rule, message_log, template) }
    message_log.save!

    DeliverMessageJob.perform_in(delay, message_log.id, result.mentioned_jids)
  end

  def schedule_is_valid
    errors.add(:base, "Informe o cron ou a data do envio único, não os dois") if cron_expression.present? == run_at.present?
    errors.add(:cron_expression, "não é uma expressão cron válida") if cron_expression.present? && Fugit.parse_cron(cron_expression).nil?
  end

  def steps_are_valid
    errors.add(:steps, "adicione pelo menos um passo") if steps.empty?

    set_names = steps.filter_map { |step| step["name"] if step["type"] == "set_variable" }
    steps.each_with_index do |step, index|
      config = STEPS[step["type"]]
      next errors.add(:steps, "#{index + 1}: tipo desconhecido") unless config

      prefix = "#{index + 1} (#{config[:label]})"
      errors.add(:steps, "#{prefix}: só funciona com gatilho de comando") if config[:sender] && !command?
      errors.add(:steps, "#{prefix}: escolha a lista") if config[:fields].include?("list_key") && whatsapp_group&.member_lists&.none? { |list| list.key == step["list_key"] }
      errors.add(:steps, "#{prefix}: informe o nome da variável") if step["type"] == "set_variable" && step["name"].blank?
      next unless step["type"] == "send_message"

      template = whatsapp_group&.templates&.find_by(id: step["template_id"])
      next errors.add(:steps, "#{prefix}: escolha o template") unless template

      missing = template.variable_names - provided_variables(template) - set_names
      errors.add(:steps, "#{prefix}: \"#{template.name}\" usa variáveis sem valor: #{missing.join(', ')}") if missing.any?
    end
  end

  def provided_variables(template)
    template.default_variables.keys + whatsapp_group.variables.keys + Template::BUILTIN_VARIABLES +
      (command? ? COMMAND_VARIABLES : []) + template.variable_names.select { |key| whatsapp_group.provides_variable?(key) }
  end
end
