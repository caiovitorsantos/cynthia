class WhatsappGroup < ApplicationRecord
  has_many :schedules, dependent: :destroy
  has_many :group_participants, dependent: :destroy
  has_many :group_rules, dependent: :destroy

  validates :jid, presence: true, uniqueness: true

  def rule(kind)
    group_rules.find { |rule| rule.kind == kind }
  end

  def provides_variable?(key)
    group_rules.any? { |rule| rule.handler.provides_variable?(rule, key) }
  end

  def render_rule_variable(key, mentioned_jids)
    group_rules.each do |rule|
      value = rule.handler.render_variable(rule, key, mentioned_jids)
      return value if value
    end
    nil
  end
end
