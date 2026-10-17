class GroupParticipant < ApplicationRecord
  ROLES = %w[mensal avulso espera].freeze

  belongs_to :whatsapp_group

  validates :jid, presence: true, uniqueness: { scope: :whatsapp_group_id }
  validates :role, inclusion: { in: ROLES }, allow_nil: true

  normalizes :role, :display_name, with: ->(value) { value.presence }

  def label
    display_name || name || phone_number
  end
end
