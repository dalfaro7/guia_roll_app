class RoleGenerator
  def initialize(work_day)
    @work_day = work_day
  end

  def generate!
    raise "WorkDay must be in draft" unless @work_day.draft?

    ActiveRecord::Base.transaction do
      reset_worked_assignments

      sorted_guides.each do |guide|
        break if rolled_count >= @work_day.guides_requested

        next unless assignable?(guide)
        assign_as_worked(guide)
      end

      ensure_full_assignments!

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
      # revierte solo worked y deja intactos standbys/días libres manuales
      gd.update!(status: nil)
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
      event: "generated",
      snapshot: {
        date: @work_day.date,
        guides_requested: @work_day.guides_requested,
        assignments: @work_day.guide_days.map { |gd| { guide_id: gd.guide_id, status: gd.status } }
      }
    )
  end
end