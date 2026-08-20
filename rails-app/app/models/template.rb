class Template < ApplicationRecord
  VARIABLE_PATTERN = /\{\{(\w+)\}\}/

  has_many :schedules, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
  validates :body, presence: true

  def variable_names
    body.to_s.scan(VARIABLE_PATTERN).flatten.uniq
  end
end
