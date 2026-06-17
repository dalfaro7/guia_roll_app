module OfficeDays
  class MonthHolidayCreditSyncer
    def initialize(month:)
      @month = month.beginning_of_month
      @month_range = @month.beginning_of_month..@month.end_of_month
      @employees = OfficeEmployee.active
    end

    def call
      OfficeHoliday.where(date: @month_range, double_pay: true).find_each do |holiday|
        @employees.each do |employee|
          sync_employee_holiday(employee, holiday.date)
        end
      end
    end

    private

    def sync_employee_holiday(employee, date)
      employee_day = OfficeEmployeeDay.find_by(
        office_employee: employee,
        date: date
      )

      should_accumulate =
        employee_day.blank? ||
        employee_day.holiday_worked? && !employee_day.holiday_paid?

      if should_accumulate
        OfficeDayCredit.find_or_create_by!(
          office_employee: employee,
          date: date,
          source: "holiday_worked"
        ) do |credit|
          credit.used = false
        end
      else
        OfficeDayCredit.where(
          office_employee: employee,
          date: date,
          source: "holiday_worked"
        ).destroy_all
      end
    end
  end
end