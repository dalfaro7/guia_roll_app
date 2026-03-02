class RoleGenerator
  def initialize(work_day)
    @work_day = work_day
  end

  def generate!
    raise "WorkDay must be draft" unless @work_day.draft?

    ActiveRecord::Base.transaction do
      reset_worked_assignments

      guides = guides_sorted_by_equity
      assigned = 0

      guides.each do |guide|
        break if assigned >= @work_day.guides_requested
        next unless available?(guide)

        assign_guide(guide)
        assigned += 1
      end

      raise ActiveRecord::Rollback if assigned < @work_day.guides_requested

      create_version_snapshot
    end
  end

  private

  def guides_sorted_by_equity
    Guide
      .left_joins(:monthly_balance)
      .where(active: true)
      .order(priority: :asc)
      .order(Arel.sql("COALESCE(monthly_balances.worked_days, 0) ASC"))
  end

  def available?(guide)
    gd = @work_day.guide_days.find_by(guide: guide)
    return true unless gd

    !gd.vacation? && !gd.day_off?
  end

  def assign_guide(guide)
    guide_day = @work_day.guide_days.find_or_initialize_by(guide: guide)

    guide_day.update!(
      status: :worked,
      manually_modified: false,
      modified_by_id: nil
    )

    increment_balance(guide)
  end

  def increment_balance(guide)
    balance = guide.monthly_balance ||
              guide.create_monthly_balance(
                month: @work_day.date.beginning_of_month,
                worked_days: 0
              )

    balance.increment!(:worked_days)
  end

  def reset_worked_assignments
    @work_day.guide_days.worked.each do |gd|
      gd.guide.monthly_balance&.decrement!(:worked_days)
      gd.destroy
    end
  end

  def create_version_snapshot
    WorkDayVersion.create!(
      work_day: @work_day,
      event: "roles_generated",
      snapshot: {
        date: @work_day.date,
        guides_requested: @work_day.guides_requested,
        assignments: @work_day.guide_days.map do |gd|
          {
            guide_id: gd.guide_id,
            status: gd.status
          }
        end
      }
    )
  end
end