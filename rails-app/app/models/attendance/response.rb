class Attendance::Response < ApplicationRecord
  self.table_name = "attendances"

  STATUSES = %w[confirmed declined].freeze

  belongs_to :message_log
  belongs_to :group_participant

  validates :status, inclusion: { in: STATUSES }
end
