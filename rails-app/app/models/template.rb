class Template < ApplicationRecord
  # {{nome}} ou {{nome:parametro}} (parâmetro usado por variáveis de regras de grupo).
  VARIABLE_PATTERN = /(?<!@)\{\{(\w+(?::\w+)?)\}\}/

  # Calculadas na hora do envio (ver TemplateRenderer), não precisam de valor no agendamento.
  # Regras de grupo (GroupRule) acrescentam as suas.
  BUILTIN_VARIABLES = %w[data mes mes_num mes_anterior].freeze

  has_many :schedules, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
  validates :body, presence: true

  def variable_names
    body.to_s.scan(VARIABLE_PATTERN).flatten.uniq
  end
end
