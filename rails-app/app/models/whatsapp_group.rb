class WhatsappGroup < ApplicationRecord
  has_many :schedules, dependent: :destroy
  has_many :group_participants, dependent: :destroy

  validates :jid, presence: true, uniqueness: true
end
