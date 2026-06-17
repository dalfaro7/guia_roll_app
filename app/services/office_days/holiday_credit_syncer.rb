module OfficeDays
  class HolidayCreditSyncer
    def initialize(employee_day:)
      @employee_day = employee_day
    end

    def call
      return unless double_pay_holiday?

      if should_have_credit?
        create_credit
      else
        destroy_credit
      end
    end

    private

    def should_have_credit?
      @employee_day.holiday_worked? && !@employee_day.holiday_paid?
    end

    def double_pay_holiday?
      OfficeHoliday.exists?(
        date: @employee_day.date,
        double_pay: true
      )
    end

    def create_credit
      OfficeDayCredit.find_or_create_by!(
        office_employee: @employee_day.office_employee,
        date: @employee_day.date,
        source: "holiday_worked"
      ) do |credit|
        credit.used = false
      end
    end

    def destroy_credit
      OfficeDayCredit
        .where(
          office_employee: @employee_day.office_employee,
          date: @employee_day.date,
          source: "holiday_worked"
        )
        .destroy_all
    end
  end
end