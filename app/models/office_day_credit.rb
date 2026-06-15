class OfficeDayCredit < ApplicationRecord
  belongs_to :office_employee

  validates :date, presence: true
  validates :office_employee_id, uniqueness: { scope: :date }

  scope :available, -> { where(used: false) }
  scope :used, -> { where(used: true) }
end