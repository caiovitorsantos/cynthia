class Billing::Charge < ApplicationRecord
  self.table_name = "charges"

  KINDS = %w[mensal avulso].freeze

  belongs_to :whatsapp_group
  belongs_to :group_participant, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :period, presence: true
  validates :guest_name, presence: true, unless: :group_participant

  scope :unpaid, -> { where(paid_at: nil) }

  def label
    group_participant&.label || guest_name
  end

  def paid? = paid_at.present?
end
