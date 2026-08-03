class OfficeEmployee < ApplicationRecord
  has_many :office_employee_days,
           dependent: :destroy

  has_many :office_day_credits,
           dependent: :destroy

  has_many :office_vacation_credits,
           dependent: :destroy

  has_many :office_overtimes,
           dependent: :destroy

  scope :active, -> { where(active: true) }

  validates :name,
            presence: true,
            uniqueness: true

  def cannot_take_day_off_on?(date)
    case name
    when "Fiorela Mena"
      date.wednesday?
    when "Yoselin Marin"
      date.wednesday? || date.friday?
    when "Priscilla Matarrita"
      date.wednesday?
    else
      false
    end
  end

  def same_department?(other_employee)
    department.present? &&
      department == other_employee.department
  end

  def available_day_credits
    office_day_credits.available.count
  end

  def available_vacation_credits
    office_vacation_credits.available.count
  end

  def overtime_minutes_for_range(range)
    office_overtimes
      .where(
        date: range,
        approved: true
      )
      .sum(:minutes)
  end

  def overtime_minutes_for_fortnight(date)
    range =
      if date.day <= 15
        date.beginning_of_month..
          date.change(day: 15)
      else
        date.change(day: 16)..
          date.end_of_month
      end

    overtime_minutes_for_range(range)
  end
end