# app/services/role_generator.rb

class RoleGenerator
  def initialize(work_day)
    @work_day = work_day
  end

  def generate!
    raise "WorkDay must be in draft state" unless @work_day.draft?

    ActiveRecord::Base.transaction do
      reset_existing_assignments

      guides = guides_sorted_by_equity
      assigned_count = 0

      guides.each do |guide|
        break if assigned_count >= @work_day.guides_requested

        next unless available?(guide)

        assign_guide(guide)
        assigned_count += 1
      end

      validate_assignment_count!(assigned_count)
      create_version_snapshot("roles_generated")
    end
  end

  private

  # ==============================
  # Core Assignment Logic
  # ==============================

  def guides_sorted_by_equity
  Guide
    .left_joins(:monthly_balance)
    .where(active: true)
    .order(priority: :asc)
    .order(Arel.sql("COALESCE(monthly_balances.worked_days, 0) ASC"))
end

  def available?(guide)
    # Solo rechaza si ya hay un GuideDay con status vacation o day_off
    existing = @work_day.guide_days.find_by(guide: guide)
    return true unless existing

    !existing.vacation? && !existing.day_off?
  end

  def assign_guide(guide)
    guide_day = @work_day.guide_days.find_or_initialize_by(guide: guide)

    guide_day.update!(
      status: :worked,
      manually_modified: false,
      modified_by: nil
    )

    increment_monthly_balance(guide)
  end

  # ==============================
  # Balance Management
  # ==============================

  def increment_monthly_balance(guide)
    balance = MonthlyBalance.find_or_create_by!(
      guide: guide,
      month: @work_day.date.beginning_of_month
    )

    balance.increment!(:worked_days)
    guide.increment!(:total_worked_days)
  end

  def decrement_monthly_balance(guide)
    balance = MonthlyBalance.find_by(
      guide: guide,
      month: @work_day.date.beginning_of_month
    )

    return unless balance

    balance.decrement!(:worked_days)
    guide.decrement!(:total_worked_days)
  end

  # ==============================
  # Reset Logic
  # ==============================

  def reset_existing_assignments
    @work_day.guide_days.each do |gd|
      if gd.status == "worked"
        decrement_monthly_balance(gd.guide)
      end
    end

    @work_day.guide_days.destroy_all
  end

  # ==============================
  # Validation
  # ==============================

  def validate_assignment_count!(count)
    if count < @work_day.guides_requested
      raise ActiveRecord::Rollback, "Not enough available guides to fulfill required count"
    end
  end

  # ==============================
  # Audit Versioning
  # ==============================

  def create_version_snapshot(event_name)
    WorkDayVersion.create!(
      work_day: @work_day,
      event: event_name,
      snapshot: snapshot_payload
    )
  end

  def snapshot_payload
    {
      date: @work_day.date,
      guides_requested: @work_day.guides_requested,
      assignments: @work_day.guide_days.map do |gd|
        {
          guide_id: gd.guide_id,
          status: gd.status,
          role_primary: gd.role_primary,
          role_secondary: gd.role_secondary
        }
      end
    }
  end
end