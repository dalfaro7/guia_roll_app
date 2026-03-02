class RoleGenerator
  def initialize(work_day)
    @work_day = work_day
    @month_date = @work_day.date.beginning_of_month
  end

  def generate!
    raise "WorkDay must be draft" unless @work_day.draft?

    ActiveRecord::Base.transaction do
      reset_previous_worked_assignments

      candidates = ordered_eligible_guides

      if candidates.size < @work_day.guides_requested
        raise "Not enough available guides"
      end

      selected_guides = candidates.first(@work_day.guides_requested)

      assign_roles(selected_guides)

      @work_day.update!(status: :generated)

      create_snapshot
    end
  end

  private

  # =====================================================
  # RESET SOLO worked (no toca vacation/day_off manuales)
  # =====================================================

  def reset_previous_worked_assignments
    @work_day.guide_days.worked.find_each do |gd|
      decrement_balance(gd.guide)

      gd.update!(
        status: :standby,
        role_primary: nil,
        role_secondary: nil
      )
    end
  end

  # =====================================================
  # ORDENAMIENTO POR PRIORIDAD + EQUIDAD MENSUAL
  # =====================================================

  def ordered_eligible_guides
    Guide.all
         .sort_by { |g| [g.priority || 999, worked_days_for(g)] }
         .select { |g| assignable?(g) }
  end

  def worked_days_for(guide)
    MonthlyBalance.find_by(
      guide: guide,
      month: @month_date
    )&.worked_days.to_i
  end

  # =====================================================
  # DISPONIBILIDAD
  # =====================================================

  def assignable?(guide)
    gd = @work_day.guide_days.find_by(guide: guide)
    return true unless gd

    !gd.vacation? && !gd.day_off?
  end

  # =====================================================
  # ASIGNACIÓN DE ROLES
  # =====================================================

  def assign_roles(selected_guides)
    selected_guides.each do |guide|
      guide_day = @work_day.guide_days.find_or_initialize_by(guide: guide)

      guide_day.update!(
        status: :worked,
        role_primary: "River Guide",
        role_secondary: nil,
        manually_modified: false
      )

      increment_balance(guide)
    end
  end

  # =====================================================
  # BALANCES
  # =====================================================

  def increment_balance(guide)
    balance = MonthlyBalance.find_or_create_by(
      guide: guide,
      month: @month_date
    )

    balance.update!(
      worked_days: balance.worked_days.to_i + 1
    )
  end

  def decrement_balance(guide)
    balance = MonthlyBalance.find_by(
      guide: guide,
      month: @month_date
    )

    return unless balance

    new_value = balance.worked_days.to_i - 1
    balance.update!(worked_days: [new_value, 0].max)
  end

  # =====================================================
  # SNAPSHOT
  # =====================================================

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
            status: gd.status,
            role_primary: gd.role_primary,
            role_secondary: gd.role_secondary
          }
        end
      }
    )
  end
end