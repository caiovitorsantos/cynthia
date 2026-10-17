class Template < ApplicationRecord
  VARIABLE_PATTERN = /(?<!@)\{\{(\w+)\}\}/

  # Calculadas na hora do envio (ver TemplateRenderer), não precisam de valor no agendamento.
  BUILTIN_VARIABLES = %w[data mes mes_num mes_anterior lista_mensais mencoes_mensais lista_espera
                         presenca_mensais presenca_avulsos mencoes_pendentes].freeze
  # Variáveis que leem a rodada de presença atual do grupo.
  ATTENDANCE_VARIABLES = %w[presenca_mensais presenca_avulsos mencoes_pendentes].freeze

  has_many :schedules, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
  validates :body, presence: true

  def variable_names
    body.to_s.scan(VARIABLE_PATTERN).flatten.uniq
  end

  def follows_attendance?
    variable_names.intersect?(ATTENDANCE_VARIABLES)
  end
end
