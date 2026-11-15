class GroupParticipant < ApplicationRecord
  belongs_to :whatsapp_group
  has_and_belongs_to_many :member_lists

  validates :jid, presence: true, uniqueness: { scope: :whatsapp_group_id }

  normalizes :display_name, with: ->(value) { value.presence }

  def label
    display_name || name || phone_number
  end

  # RF-29: rótulo para o que vai à Anthropic. Nunca o telefone nem o JID.
  def ai_label
    display_name || name || "Participante ##{id}"
  end
end
