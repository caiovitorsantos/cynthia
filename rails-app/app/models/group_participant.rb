class GroupParticipant < ApplicationRecord
  belongs_to :whatsapp_group

  validates :jid, presence: true, uniqueness: { scope: :whatsapp_group_id }
end
