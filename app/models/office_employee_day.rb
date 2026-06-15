class OfficeEmployeeDay < ApplicationRecord
  belongs_to :office_employee

  enum :status, {
    day_off: 1,
    vacation: 2,
    sick_leave: 3,
    unjustified_absence: 4,
    holiday_worked: 5
  }

  validates :date, presence: true
  validates :office_employee_id, uniqueness: { scope: :date }

  def accumulates_holiday_credit?
    holiday_worked? && !holiday_paid?
  end

  def uses_credit?
    day_off? && day_off_source == "credit"
  end
end