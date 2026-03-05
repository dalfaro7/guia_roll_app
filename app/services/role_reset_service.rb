class RoleResetService

  def initialize(work_day)
    @work_day = work_day
    @month = @work_day.date.beginning_of_month
  end

  # RESET COMPLETO DEL ROLL
  def call
    ActiveRecord::Base.transaction do

      restore_day_off_balances

      revert_balances

      clear_worked_assignments

      @work_day.work_day_versions.destroy_all

      @work_day.update!(
        status: :draft,
        published_at: nil
      )

    end
  end

  # USADO POR UNPUBLISH
  # SOLO REVIERTE BALANCES SIN LIMPIAR ROLES
  def revert_only_balances
    ActiveRecord::Base.transaction do

      restore_day_off_balances

      revert_balances

    end
  end

  private

  # DEVOLVER DAY OFF CONSUMIDOS
  def restore_day_off_balances

    @work_day.guide_days
             .where(status: :day_off, day_off_consumed: true)
             .includes(:guide)
             .each do |guide_day|

      guide = guide_day.guide

      guide.update!(
        day_off_balance: guide.day_off_balance.to_i + 1
      )

      guide_day.update!(
        day_off_consumed: false
      )

    end

  end

  # REVERTIR WORKED DAYS
  def revert_balances

    @work_day.guide_days
             .worked
             .includes(:guide)
             .find_each do |guide_day|

      decrement_balance(guide_day.guide)

    end

  end

  # LIMPIAR ROLES Y STATUS
  def clear_worked_assignments

    @work_day.guide_days.find_each do |guide_day|

      guide_day.update!(
        status: :standby,
        role_primary: nil,
        role_secondary: nil,
        location: nil,
        manually_modified: false,
        modified_by_id: nil,
        day_off_consumed: false
      )

    end

  end

  def decrement_balance(guide)

    balance = guide.monthly_balances.find_by(month: @month)
    return unless balance

    new_value = balance.worked_days.to_i - 1

    balance.update!(
      worked_days: [new_value, 0].max
    )

    if guide.total_worked_days.to_i > 0
      guide.decrement!(:total_worked_days)
    end

  end

end