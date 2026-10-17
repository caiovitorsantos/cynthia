class MessageLog < ApplicationRecord
  STATUSES = %w[pending sent failed].freeze

  belongs_to :schedule, optional: true

  validates :status, inclusion: { in: STATUSES }

  def mark_sent!(wa_message_id)
    update!(status: "sent", sent_at: Time.current, wa_message_id: wa_message_id)

    group = WhatsappGroup.find_by(jid: group_jid)
    group&.group_rules&.each { |rule| rule.handler.after_send(rule, self) }
  end
end
