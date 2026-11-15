class MessageLog < ApplicationRecord
  STATUSES = %w[pending sent failed].freeze
  AI_NOTICE = "ai_notice".freeze # RF-28: aviso de IA de terceiro, um por grupo

  belongs_to :flow, optional: true

  validates :status, inclusion: { in: STATUSES }

  # ID interno do grupo para eventos (group_jid nunca vai para analytics_events: pode conter telefone).
  def whatsapp_group_id
    WhatsappGroup.where(jid: group_jid).pick(:id)
  end

  def mark_sent!(wa_message_id)
    update!(status: "sent", sent_at: Time.current, wa_message_id: wa_message_id)
  end
end
