class MessageLog < ApplicationRecord
  STATUSES = %w[pending sent failed].freeze

  belongs_to :schedule, optional: true

  validates :status, inclusion: { in: STATUSES }
end
