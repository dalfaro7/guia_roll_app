class CompensationAdjustment < ApplicationRecord
  belongs_to :compensation_settlement
  belongs_to :source_assignment, class_name: "CompensationAssignment"
  belongs_to :created_by, class_name: "User"

  validates :reason, presence: true
  validates :amount_cents, numericality: { only_integer: true }
end
