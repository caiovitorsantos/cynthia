class GroupParticipant < ApplicationRecord
  belongs_to :whatsapp_group

  validates :jid, presence: true, uniqueness: { scope: :whatsapp_group_id }

  normalizes :role, :display_name, with: ->(value) { value.presence }

  def label
    display_name || name || phone_number
  end
end
