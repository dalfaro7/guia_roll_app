class CompensationLine < ApplicationRecord
  belongs_to :compensation_assignment
  belongs_to :compensation_rate, optional: true

  validates :code, presence: true, uniqueness: { scope: :compensation_assignment_id }
  validates :rate_cents, :amount_cents, numericality: { only_integer: true }
  validates :discount_percent, numericality: {
    only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100
  }
  validates :applied_at, presence: true
end
