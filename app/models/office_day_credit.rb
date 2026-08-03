class OfficeDayCredit < ApplicationRecord
  belongs_to :office_employee

  has_one :office_employee_day,
          dependent: :nullify

  validates :date, presence: true
  validates :source, presence: true

  validates :office_employee_id,
            uniqueness: {
              scope: [:date, :source],
              message: "ya tiene un acumulado de este origen para esta fecha"
            }

  scope :available, -> { where(used: false) }
  scope :used, -> { where(used: true) }
  scope :legacy, -> { where(source: "legacy") }
  scope :holiday_worked, -> { where(source: "holiday_worked") }

  def available?
    !used?
  end
end