module OfficeDays
  class DayOffGenerator
    def initialize(month:)
      @month = month.beginning_of_month

      @month_range =
        @month.beginning_of_month..@month.end_of_month

      @generation_range =
        @month.beginning_of_month.beginning_of_week(:monday)..
        @month.end_of_month.end_of_week(:monday)

      @employees = OfficeEmployee.active.order(:name)
    end

    def call
      generate_required_saturdays
      generate_required_sundays
      generate_remaining_weekly_days
    end

    private

    def generate_required_saturdays
      generate_required_weekend_day(:saturday)
    end

    def generate_required_sundays
      generate_required_weekend_day(:sunday)
    end

    def generate_required_weekend_day(day_type)
      @employees.each do |employee|
        next if employee_has_weekend_day?(employee, day_type)

        date = available_weekend_dates_for(employee, day_type).first
        next unless date

        create_day_off(employee, date)
      end
    end

    def generate_remaining_weekly_days
      weeks_in_month.each do |week_range|
        @employees.each do |employee|
          next if employee_already_has_day_off_this_week?(employee, week_range)

          date = best_available_weekday_for(employee, week_range)
          next unless date

          create_day_off(employee, date)
        end
      end
    end

    def create_day_off(employee, date)
      OfficeEmployeeDay.create!(
        office_employee: employee,
        date: date,
        status: :day_off,
        day_off_source: "automatic"
      )
    end

    def available_weekend_dates_for(employee, day_type)
      weekend_dates(day_type)
        .reject { |date| employee.cannot_take_day_off_on?(date) }
        .reject { |date| OfficeEmployeeDay.exists?(office_employee: employee, date: date) }
        .reject { |date| employee_already_has_day_off_this_week?(employee, week_range_for(date)) }
        .reject { |date| department_conflict_on_date?(employee, date) }
        .sort_by { |date| weekend_date_score(employee, date) }
    end

    def best_available_weekday_for(employee, week_range)
      week_range
        .select { |date| @generation_range.cover?(date) }
        .reject { |date| date.saturday? || date.sunday? }
        .reject { |date| employee.cannot_take_day_off_on?(date) }
        .reject { |date| OfficeEmployeeDay.exists?(office_employee: employee, date: date) }
        .reject { |date| department_conflict_on_date?(employee, date) }
        .sort_by { |date| weekday_score(employee, date) }
        .first
    end

    def employee_has_weekend_day?(employee, day_type)
      OfficeEmployeeDay
        .where(office_employee: employee, status: :day_off)
        .where(date: @generation_range)
        .where("EXTRACT(DOW FROM date) = ?", day_type == :sunday ? 0 : 6)
        .exists?
    end

    def employee_already_has_day_off_this_week?(employee, week_range)
      OfficeEmployeeDay
        .where(office_employee: employee, status: :day_off)
        .where(date: week_range)
        .exists?
    end

    def department_conflict_on_date?(employee, date)
      return false if employee.department.blank?

      OfficeEmployeeDay
        .includes(:office_employee)
        .where(date: date, status: :day_off)
        .any? do |day|
          day.office_employee.department.present? &&
            day.office_employee.department == employee.department
        end
    end

    def weekend_dates(day_type)
      @generation_range.select do |date|
        day_type == :saturday ? date.saturday? : date.sunday?
      end
    end

    def weekend_date_score(employee, date)
      [
        day_offs_on_date(date),
        total_generation_day_offs(employee),
        date
      ]
    end

    def weekday_score(employee, date)
      [
        same_weekday_count(employee, date),
        day_offs_on_date(date),
        total_generation_day_offs(employee),
        date
      ]
    end

    def same_weekday_count(employee, date)
      OfficeEmployeeDay
        .where(office_employee: employee, status: :day_off)
        .where(date: @generation_range)
        .where("EXTRACT(DOW FROM date) = ?", date.wday)
        .count
    end

    def day_offs_on_date(date)
      OfficeEmployeeDay
        .where(date: date, status: :day_off)
        .count
    end

    def total_generation_day_offs(employee)
      OfficeEmployeeDay
        .where(office_employee: employee, status: :day_off)
        .where(date: @generation_range)
        .count
    end

    def week_range_for(date)
      date.beginning_of_week(:monday)..date.end_of_week(:monday)
    end

    def weeks_in_month
      weeks = []
      current = @generation_range.begin

      while current <= @generation_range.end
        weeks << (current..current.end_of_week(:monday))
        current += 1.week
      end

      weeks
    end
  end
end