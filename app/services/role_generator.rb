class RoleGenerator
  def initialize(work_day)
    @work_day = work_day
  end

  def call
    raise "WorkDay must be draft" unless @work_day.draft?

    ActiveRecord::Base.transaction do
      generate_roles
      update_balances
      save_snapshot
      @work_day.update!(status: :generated)
    end
  end

  private

  def generate_roles
    guides = guides_sorted_by_priority
    assigned = 0

    guides.each do |guide|
      status =
        if assigned < @work_day.guides_requested
          assigned += 1
          :worked
        else
          :standby
        end

      GuideDay.create!(
        guide: guide,
        work_day: @work_day,
        status: status,
        role_primary: status == :worked ? "River Guide" : nil,
        manually_modified: false
      )
    end
  end

  def guides_sorted_by_priority
    Guide.active.order(:priority, :total_worked_days)
  end

  def update_balances
    month_date = @work_day.date.beginning_of_month

    @work_day.guide_days.worked.each do |gd|
      balance = MonthlyBalance.find_or_initialize_by(
        guide: gd.guide,
        month: month_date
      )

      balance.worked_days ||= 0
      balance.worked_days += 1
      balance.save!

      gd.guide.increment!(:total_worked_days)
    end
  end

  def save_snapshot
    WorkDayVersion.create!(
      work_day: @work_day,
      snapshot: {
        guides: @work_day.guide_days.map do |gd|
          {
            guide_id: gd.guide_id,
            status: gd.status,
            role_primary: gd.role_primary
          }
        end
      }
    )
  end
end