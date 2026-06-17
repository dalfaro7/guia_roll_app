module OfficeDays
  class MonthHolidayCreditSyncer
    def initialize(month:)
      @month = month.beginning_of_month
      @month_range = @month.beginning_of_month..@month.end_of_month
      @employees = OfficeEmployee.active
    end

    def call
      double_pay_holidays.find_each do |holiday|
        @employees.each do |employee|
          next if employee_is_not_working_on?(employee, holiday.date)
          next if holiday_paid_record?(employee, holiday.date)

          OfficeDayCredit.find_or_create_by!(
            office_employee: employee,
            date: holiday.date,
            source: "holiday_worked"
          ) do |credit|
            credit.used = false
          end
        end
      end
    end

    private

    def double_pay_holidays
      OfficeHoliday.where(date: @month_range, double_pay: true)
    end

    def employee_is_not_working_on?(employee, date)
      OfficeEmployeeDay.exists?(
        office_employee: employee,
        date: date,
        status: [
          OfficeEmployeeDay.statuses[:day_off],
          OfficeEmployeeDay.statuses[:vacation],
          OfficeEmployeeDay.statuses[:sick_leave],
          OfficeEmployeeDay.statuses[:unjustified_absence]
        ]
      )
    end

    def holiday_paid_record?(employee, date)
      OfficeEmployeeDay.exists?(
        office_employee: employee,
        date: date,
        status: :holiday_worked,
        holiday_paid: true
      )
    end
  end
end