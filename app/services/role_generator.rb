class RoleGenerator
  def initialize(work_day)
    @work_day = work_day
  end

  def generate!
  raise "WorkDay must be draft" unless @work_day.draft?

  ActiveRecord::Base.transaction do
    reset_worked_assignments

    available_guides = sorted_guides.select { |g| assignable?(g) }

    if available_guides.size < @work_day.guides_requested
      raise "Not enough available guides"
    end

    available_guides
      .first(@work_day.guides_requested)
      .each { |guide| assign_as_worked(guide) }

    snapshot_roll!
  end
end

  private

  def sorted_guides
    Guide
      .left_joins(:monthly_balance)
      .where(active: true)
      .order(priority: :asc)
      .order(Arel.sql("COALESCE(monthly_balances.worked_days, 0) ASC"))
  end

  def assignable?(guide)
    gd = @work_day.guide_days.find_by(guide: guide)
    return true unless gd

    !gd.vacation? && !gd.day_off?
  end

  def assign_as_worked(guide)
    gd = @work_day.guide_days.find_or_initialize_by(guide: guide)
    gd.assign_attributes(status: :worked)
    gd.manually_modified = false
    gd.save!
  end

  def reset_worked_assignments
  @work_day.guide_days.worked.each do |gd|
    gd.update!(status: :standby)
  end
end

  def rolled_count
    @work_day.guide_days.worked.count
  end

  def ensure_full_assignments!
    if rolled_count < @work_day.guides_requested
      raise ActiveRecord::Rollback, "Not enough assignable guides"
    end
  end

  def snapshot_roll!
  WorkDayVersion.create!(
    work_day: @work_day,
    snapshot: {
      type: "generated",
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