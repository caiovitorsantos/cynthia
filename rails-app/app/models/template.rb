class Template < ApplicationRecord
  VARIABLE_PATTERN = /(?<!@)\{\{(\w+)\}\}/

  # Calculadas na hora do envio (ver TemplateRenderer), não precisam de valor no agendamento.
  BUILTIN_VARIABLES = %w[data mes mes_num mes_anterior lista_mensais mencoes_mensais lista_espera].freeze

  has_many :schedules, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
  validates :body, presence: true

  def variable_names
    body.to_s.scan(VARIABLE_PATTERN).flatten.uniq
  end
end
