class CompensationLine < ApplicationRecord
  belongs_to :compensation_assignment
  belongs_to :compensation_rate, optional: true

  validates :code, presence: true, uniqueness: { scope: :compensation_assignment_id }
  validates :rate_cents, :amount_cents, numericality: { only_integer: true }
  validates :discount_percent, inclusion: { in: [0, 30] }
  validates :applied_at, presence: true
end
