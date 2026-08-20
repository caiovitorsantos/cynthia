class Schedule < ApplicationRecord
  belongs_to :template
  belongs_to :whatsapp_group

  has_many :message_logs, dependent: :nullify

  validate :cron_expression_xor_run_at
  validate :cron_expression_is_valid
  validate :template_variables_present

  private

  def cron_expression_xor_run_at
    return if cron_expression.present? != run_at.present?

    errors.add(:base, "Informe cron_expression ou run_at, mas não os dois")
  end

  def cron_expression_is_valid
    return if cron_expression.blank?

    errors.add(:cron_expression, "não é uma expressão cron válida") if Fugit.parse_cron(cron_expression).nil?
  end

  def template_variables_present
    return unless template

    provided = variables.to_h.stringify_keys.keys + template.default_variables.to_h.stringify_keys.keys
    missing = template.variable_names - provided

    errors.add(:variables, "faltando valores para: #{missing.join(', ')}") if missing.any?
  end
end
