class MessageLog < ApplicationRecord
  STATUSES = %w[pending sent failed].freeze

  belongs_to :schedule, optional: true
  belongs_to :round, class_name: "MessageLog", optional: true

  has_many :attendances, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }

  # Rodada = envio com sucesso de um template marcado como lista de presença.
  scope :rounds, -> { where(status: "sent").where.not(wa_message_id: nil).joins(schedule: :template).where(templates: { attendance: true }) }

  def self.current_round(whatsapp_group)
    rounds.where(group_jid: whatsapp_group.jid).order(sent_at: :desc).first
  end

  # A rodada a que esta mensagem pertence: ela mesma se for a lista, ou a que ela acompanha.
  def attendance_round
    schedule&.template&.attendance? ? self : round
  end
end
