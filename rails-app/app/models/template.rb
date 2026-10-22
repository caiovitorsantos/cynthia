class Template < ApplicationRecord
  # {{nome}} ou {{nome:parametro}} (parâmetro usado por listas e regras de grupo).
  VARIABLE_PATTERN = /(?<!@)\{\{(\w+(?::\w+)?)\}\}/

  # Calculadas na hora do envio (ver TemplateRenderer), não precisam de valor.
  # Listas e regras de grupo acrescentam as suas.
  BUILTIN_VARIABLES = %w[data mes mes_num mes_anterior].freeze

  belongs_to :whatsapp_group

  validates :name, presence: true, uniqueness: { scope: :whatsapp_group_id }
  validates :body, presence: true

  before_destroy :ensure_unused, unless: :destroyed_by_association # apagar o grupo leva os fluxos junto

  def variable_names
    body.to_s.scan(VARIABLE_PATTERN).flatten.uniq
  end

  private

  def ensure_unused
    used_by = whatsapp_group.flows.select { |flow| flow.template_ids.include?(id) }
    return if used_by.empty?

    errors.add(:base, "usado pelos fluxos: #{used_by.map(&:name).join(', ')}")
    throw :abort
  end
end
