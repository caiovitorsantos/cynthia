class WhatsappGroup < ApplicationRecord
  has_many :schedules, dependent: :restrict_with_error

  validates :jid, presence: true, uniqueness: true
end
