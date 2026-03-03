class RoleResetService
  def initialize(work_day)
    @work_day = work_day
    @month = @work_day.date.beginning_of_month
  end

  def call
    ActiveRecord::Base.transaction do
      revert_balances
      clear_worked_assignments

      @work_day.work_day_versions.destroy_all

      @work_day.update!(
        status: :draft,
        published_at: nil
      )
    end
  end

  def revert_only_balances
    ActiveRecord::Base.transaction do
      revert_balances
    end
  end

  private

  # SOLO BALANCES
  def revert_balances
    @work_day.guide_days.worked.includes(:guide).find_each do |guide_day|
      decrement_balance(guide_day.guide)
    end
  end

  # SOLO LIMPIEZA DE ROLES + STATUS
  def clear_worked_assignments
    @work_day.guide_days.worked.find_each do |guide_day|
      guide_day.update!(
        status: :standby,
        role_primary: nil,
        role_secondary: nil,
        manually_modified: false,
        modified_by_id: nil
      )
    end
  end

  def decrement_balance(guide)
    balance = guide.monthly_balances.find_by(month: @month)
    return unless balance

    new_value = balance.worked_days.to_i - 1
    balance.update!(worked_days: [new_value, 0].max)

    guide.decrement!(:total_worked_days) if guide.total_worked_days.to_i > 0
  end
end