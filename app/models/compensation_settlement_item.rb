class CompensationSettlementItem < ApplicationRecord
  belongs_to :compensation_settlement
  belongs_to :compensation_assignment

  validates :amount_cents, numericality: { only_integer: true }
  validates :compensation_assignment_id,
    uniqueness: { scope: :compensation_settlement_id }
end
