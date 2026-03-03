class RoleResetService
  def initialize(work_day)
    @work_day = work_day
    @month = @work_day.date.beginning_of_month
  end

  def call
    ActiveRecord::Base.transaction do
      revert_balances

      @work_day.guide_days.update_all(
  role_primary: nil,
  role_secondary: nil,
  status: 1, # o el valor que represente "draft" o "available"
  manually_modified: false,
  modified_by_id: nil
)

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

  def revert_balances
    @work_day.guide_days.worked.includes(:guide).each do |guide_day|
      guide = guide_day.guide
      balance = guide.monthly_balances.find_by(month: @month)

      balance.decrement!(:worked_days) if balance&.worked_days.to_i > 0
      guide.decrement!(:total_worked_days) if guide.total_worked_days.to_i > 0
    end
  end
end