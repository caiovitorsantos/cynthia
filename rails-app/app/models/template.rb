class Template < ApplicationRecord
  # {{nome}} ou {{nome:parametro}} (parâmetro usado por listas e regras de grupo).
  VARIABLE_PATTERN = /(?<!@)\{\{(\w+(?::\w+)?)\}\}/
  # Qualquer {{...}} que não é menção. Para a validação: o que não casa com VARIABLE_PATTERN (hífen,
  # espaço) sairia literal no grupo, então conta como variável sem fonte (RF-06, WHA-20).
  PLACEHOLDER_PATTERN = /(?<!@)\{\{([^{}]+)\}\}/

  # Calculadas na hora do envio (ver TemplateRenderer), não precisam de valor.
  # Listas e regras de grupo acrescentam as suas.
  BUILTIN_VARIABLES = %w[data mes mes_num mes_anterior].freeze

  belongs_to :whatsapp_group

  validates :name, presence: true, uniqueness: { scope: :whatsapp_group_id }
  validates :body, presence: true

  before_destroy :ensure_unused, unless: :destroyed_by_association # apagar o grupo leva os fluxos junto

  # Nome digitado ("Chave Pix", "e2e-lista") → chave que cabe em {{chave}}: só letras, dígitos e "_".
  # parameterize mantém o hífen, que \w não aceita; por isso o tr antes.
  def self.key_for(name)
    name.to_s.tr("-", " ").parameterize(separator: "_")
  end

  def variable_names
    body.to_s.scan(PLACEHOLDER_PATTERN).flatten.uniq
  end

  private

  def ensure_unused
    used_by = whatsapp_group.flows.select { |flow| flow.template_ids.include?(id) }
    return if used_by.empty?

    errors.add(:base, :used_by_flows, flows: used_by.map(&:name).join(", "))
    throw :abort
  end
end
