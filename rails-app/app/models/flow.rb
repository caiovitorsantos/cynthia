# Automação de um grupo: um gatilho (horário ou comando "!algo" no grupo) e passos executados
# em ordem. Fluxo de horário é a "rotina". Os passos são os componentes de STEPS; os que agem
# sobre "quem mandou" só fazem sentido em fluxos de comando.
class Flow < ApplicationRecord
  TRIGGERS = %w[schedule command].freeze

  STEPS = {
    "send_message" => { fields: %w[template_id opens_round opens_billing] },
    "add_to_list" => { fields: %w[list_key], sender: true },
    "remove_from_list" => { fields: %w[list_key], sender: true },
    "clear_list" => { fields: %w[list_key] },
    "set_variable" => { fields: %w[name value] }
  }.freeze

  # Disponíveis nos templates e valores de passos de um fluxo de comando.
  COMMAND_VARIABLES = %w[remetente argumento].freeze

  belongs_to :whatsapp_group
  has_many :message_logs, dependent: :nullify

  normalizes :command, with: ->(value) { value.strip.downcase.presence }

  validates :name, presence: true
  validates :trigger, inclusion: { in: TRIGGERS }
  validates :command, presence: true, format: { with: /\A!\S+\z/, message: :command_format }, if: :command?
  validate :schedule_is_valid, if: :schedule?
  validate :steps_are_valid

  before_validation :clear_other_trigger_fields
  before_save :plan_next_run, if: -> { will_save_change_to_trigger? || will_save_change_to_cron_expression? || will_save_change_to_run_at? || will_save_change_to_timezone? }

  scope :active, -> { where(active: true) }

  # Linhas do formulário → passos, só com os campos do tipo escolhido. Linha sem tipo é descartada.
  # Todos os campos que algum tipo de passo aceita (para o permit do formulário).
  STEP_FIELDS = STEPS.values.flat_map { |step| step[:fields] }.uniq.freeze

  def self.steps_from(rows)
    rows.to_h.values.filter_map do |row|
      step = STEPS[row[:type]]
      next unless step

      values = step[:fields].index_with { |field| row[field].to_s.strip }.compact_blank
      values["name"] = Template.key_for(values["name"]) if values.key?("name")
      { "type" => row[:type] }.merge(values)
    end
  end

  def self.for_command(text)
    active.where(trigger: "command", command: text.to_s.strip.downcase.split.first)
  end

  def schedule? = trigger == "schedule"
  def command? = trigger == "command"

  # Mexe em dados do grupo (variáveis, esvaziar lista)? Então, por comando, só admin pode rodar.
  # Pôr/tirar a si mesmo de uma lista (ex.: !espera) continua liberado para todos.
  def modifies_group?
    steps.any? { |step| %w[set_variable clear_list].include?(step["type"]) }
  end

  def template_ids
    steps.filter_map { |step| step["template_id"].to_i if step["type"] == "send_message" }
  end

  # context (fluxo de comando): "sender_jid", "push_name" e "text" da mensagem do comando. "origem" (rotina,
  # comando, executar_agora) e "agendado_para" só vão para o evento fluxo_executado (tracking-plan).
  def run!(context = {})
    AnalyticsEvent.track(:fluxo_executado, flow_id: id, whatsapp_group_id: whatsapp_group_id, origem: context["origem"],
                                           agendado_para: context["agendado_para"], passos: steps.size)
    sender = whatsapp_group.participant_for!(context["sender_jid"], context["push_name"]) if context["sender_jid"].present?
    variables = sender ? { "remetente" => sender.label, "argumento" => context["text"].to_s.strip.split(" ", 2)[1].to_s } : {}
    delay = 0

    steps.each do |step|
      next if STEPS[step["type"]][:sender] && !sender # comando do próprio número conectado chega sem remetente
      list = whatsapp_group.member_lists.find_by!(key: step["list_key"]) if step["list_key"].present?

      case step["type"]
      when "send_message"
        send_template(whatsapp_group.templates.find(step["template_id"]), variables, step, delay: delay, origem: context["origem"])
        # ponytail: espaça os envios pela janela do SendGuard; fila por grupo se ficar lento.
        delay += SendGuard::THROTTLE_WINDOW + 1
      when "add_to_list" then list.group_participants << sender unless list.group_participants.include?(sender)
      when "remove_from_list" then list.group_participants.delete(sender)
      when "clear_list" then list.group_participants.clear
      when "set_variable"
        value = TemplateRenderer.call(Template.new(body: step["value"].to_s), variables, whatsapp_group: whatsapp_group).body
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

  def send_template(template, variables, step, delay:, origem:)
    now = Time.current.in_time_zone(timezone)
    whatsapp_group.group_rules.each { |rule| rule.handler.before_message(rule, step, now) }
    result = TemplateRenderer.call(template, variables, whatsapp_group: whatsapp_group, now: now)
    signature = whatsapp_group.signature_sample
    body = command? && signature ? "#{result.body}\n\n#{signature}" : result.body
    message_log = message_logs.new(group_jid: whatsapp_group.jid, rendered_body: body, status: "pending",
                                       opens_round: step["opens_round"] == "1", opens_billing: step["opens_billing"] == "1")
    whatsapp_group.group_rules.each { |rule| rule.handler.prepare_message(rule, message_log, template) }
    message_log.save!

    DeliverMessageJob.perform_in(delay, message_log.id, result.mentioned_jids, origem)
  end

  def schedule_is_valid
    errors.add(:base, :cron_xor_run_at) if cron_expression.present? == run_at.present?
    errors.add(:cron_expression, :invalid_cron) if cron_expression.present? && Fugit.parse_cron(cron_expression).nil?
  end

  def steps_are_valid
    errors.add(:steps, :empty_steps) if steps.empty?

    set_names = steps.filter_map { |step| step["name"] if step["type"] == "set_variable" }
    steps.each_with_index do |step, index|
      config = STEPS[step["type"]]
      next errors.add(:steps, :unknown_step, step: index + 1) unless config

      prefix = { step: "#{index + 1} (#{I18n.t("flow_steps.#{step["type"]}")})" }
      errors.add(:steps, :sender_only, **prefix) if config[:sender] && !command?
      errors.add(:steps, :choose_list, **prefix) if config[:fields].include?("list_key") && whatsapp_group&.member_lists&.none? { |list| list.key == step["list_key"] }
      errors.add(:steps, :variable_name, **prefix) if step["type"] == "set_variable" && step["name"].blank?
      next unless step["type"] == "send_message"

      template = whatsapp_group&.templates&.find_by(id: step["template_id"])
      next errors.add(:steps, :choose_template, **prefix) unless template

      missing = template.variable_names - provided_variables(template) - set_names
      errors.add(:steps, :missing_variables, **prefix, template: template.name, variables: missing.join(", ")) if missing.any?
    end
  end

  def provided_variables(template)
    template.default_variables.keys + whatsapp_group.variables.keys + Template::BUILTIN_VARIABLES +
      (command? ? COMMAND_VARIABLES : []) + template.variable_names.select { |key| whatsapp_group.provides_variable?(key) }
  end
end
