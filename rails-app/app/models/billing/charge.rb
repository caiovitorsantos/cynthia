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

  def ai_label = group_participant&.ai_label || guest_name # RF-29

  def paid? = paid_at.present?

  def event_properties = { charge_id: id, whatsapp_group_id: whatsapp_group_id, periodo: period } # sem nome (tracking-plan)
end
