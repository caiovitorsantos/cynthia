class MessageLog < ApplicationRecord
  STATUSES = %w[pending sent failed].freeze

  belongs_to :flow, optional: true

  validates :status, inclusion: { in: STATUSES }

  def mark_sent!(wa_message_id)
    update!(status: "sent", sent_at: Time.current, wa_message_id: wa_message_id)
  end
end
