class RoleGenerator
  def initialize(work_day)
    @work_day = work_day
  end

  def generate!
    raise "WorkDay must be draft" unless @work_day.draft?

    ActiveRecord::Base.transaction do
      reset_previous_worked

      candidates = eligible_guides

      if candidates.size < @work_day.guides_requested
        raise "Not enough available guides"
      end

      selected_guides = candidates.first(@work_day.guides_requested)

      selected_guides.each do |guide|
        guide_day = @work_day.guide_days.find_or_initialize_by(guide: guide)

        guide_day.update!(
          status: :worked,
          manually_modified: false,
          modified_by_id: nil
        )
      end

      @work_day.update!(status: :generated)

      create_snapshot
    end
  end

  private

  # ============================
  # RESET SOLO worked
  # ============================

  def reset_previous_worked
    @work_day.guide_days.worked.update_all(status: GuideDay.statuses[:standby])
  end

  # ============================
  # SELECCIÓN ORDENADA
  # ============================

  def eligible_guides
    Guide.all
         .sort_by { |g| [g.priority || 999, worked_days_for(g)] }
         .select { |g| assignable?(g) }
  end

  def worked_days_for(guide)
    guide.monthly_balance&.worked_days || 0
  end

  # ============================
  # DISPONIBILIDAD
  # ============================

  def assignable?(guide)
    gd = @work_day.guide_days.find_by(guide: guide)
    return true unless gd

    !gd.vacation? && !gd.day_off?
  end

  # ============================
  # SNAPSHOT
  # ============================

  def create_snapshot
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