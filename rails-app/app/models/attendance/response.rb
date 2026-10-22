# Resposta de um membro (group_participant) ou de um convidado sem cadastro (guest_name, vindo
# de uma lista colada no grupo) a uma rodada.
class Attendance::Response < ApplicationRecord
  self.table_name = "attendances"

  STATUSES = %w[confirmed declined].freeze

  belongs_to :message_log
  belongs_to :group_participant, optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :guest_name, presence: true, unless: :group_participant
end
