module OfficeDays
  class DayOffGenerator
    def initialize(month:)
  @month = month.beginning_of_month

  @month_range =
    @month.beginning_of_month..@month.end_of_month

  @generation_range =
    @month.beginning_of_month.beginning_of_week(:monday)..
    @month.end_of_month.end_of_week(:monday)

  @employees = OfficeEmployee.active.to_a

  @holiday_dates =
    OfficeHoliday
      .where(date: @generation_range)
      .pluck(:date)
end

    def call
      OfficeEmployeeDay.transaction do
        generate_required_saturdays
        generate_required_sundays
        generate_remaining_weekly_days
      end
    end

    private

    def holiday?(date)
  @holiday_dates.include?(date)
end

    def employees_randomized_for(week_range)
  seed = @month.year * 10_000 +
         @month.month * 100 +
         week_range.begin.day

  @employees.shuffle(random: Random.new(seed))
end

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
    employees_randomized_for(week_range).each do |employee|
      next if employee_already_has_day_off_this_week?(employee, week_range)

      date = best_available_weekday_for(employee, week_range)
      next unless date

      create_day_off(employee, date)
    end
  end
end

    # Existing weekly assignments are preserved; only new days are paired.
    def assignment_group(employee)
      names = ["Fiorela Mena", "Manuel Anchia"]
      return [employee] unless names.include?(employee.name)

      @employees.select { |candidate| names.include?(candidate.name) }
    end

    def available_for_group?(employee, date)
      return false if holiday?(date)

      assignment_group(employee).all? do |member|
        !member.cannot_take_day_off_on?(date) &&
          !OfficeEmployeeDay.exists?(office_employee: member, date: date) &&
          !employee_already_has_day_off_this_week?(member, week_range_for(date)) &&
          !department_conflict_on_date?(member, date)
      end
    end

    def create_day_off(employee, date)
      return unless available_for_group?(employee, date)

      OfficeEmployeeDay.transaction do
        assignment_group(employee).each do |member|
          OfficeEmployeeDay.create!(office_employee: member, date: date,
            status: :day_off, day_off_source: "automatic")
        end
      end
    end

    def available_weekend_dates_for(employee, day_type)
      weekend_dates(day_type)
        .select { |date| available_for_group?(employee, date) }
        .sort_by { |date| weekend_date_score(employee, date) }
    end

    def best_available_weekday_for(employee, week_range)
      week_range
        .select { |date| @generation_range.cover?(date) }
        .reject { |date| date.saturday? || date.sunday? }
        .select { |date| available_for_group?(employee, date) }
        .sort_by { |date| weekday_score(employee, date) }
        .first
    end

    def employee_has_weekend_day?(employee, day_type)
  OfficeEmployeeDay
    .where(office_employee: employee, status: :day_off)
    .where(date: @month_range)
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
  @month_range.select do |date|
    day_type == :saturday ? date.saturday? : date.sunday?
  end
end

    def weekend_date_score(employee, date)
  [
    day_offs_on_date(date),
    total_generation_day_offs(employee),
    random_date_value(employee, date)
  ]
end

    def weekday_score(employee, date)
  [
    same_weekday_count(employee, date),
    day_offs_on_date(date),
    total_generation_day_offs(employee),
    random_date_value(employee, date)
  ]
end

def random_date_value(employee, date)
  seed =
    employee.id * 100_000 +
    date.year * 1_000 +
    date.yday

  Random.new(seed).rand
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