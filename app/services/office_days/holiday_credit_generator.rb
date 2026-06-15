module OfficeDays
  class HolidayCreditGenerator
    def initialize(date:)
      @date = date
    end

    def call
      holiday = OfficeHoliday.find_by(date: @date, double_pay: true)
      return unless holiday

      OfficeEmployeeDay
        .where(date: @date, status: :holiday_worked, holiday_paid: false)
        .find_each do |employee_day|

        OfficeDayCredit.find_or_create_by!(
          office_employee: employee_day.office_employee,
          date: @date
        ) do |credit|
          credit.source = "holiday_worked"
          credit.used = false
        end
      end
    end
  end
end