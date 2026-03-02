class RoleResetService
  def initialize(work_day)
    @work_day = work_day
  end

  def call
    ActiveRecord::Base.transaction do
      revert_balances
      @work_day.guide_days.destroy_all
      @work_day.work_day_versions.destroy_all
      @work_day.update!(status: :draft, published_at: nil)
    end
  end

  private

  def revert_balances
    worked_assignments = @work_day.guide_days.worked

    worked_assignments.each do |guide_day|
      guide = guide_day.guide
      month = @work_day.date.beginning_of_month

      balance = MonthlyBalance.find_by(guide: guide, month: month)
      next unless balance

      balance.update!(
        worked_days: [balance.worked_days - 1, 0].max
      )

      guide.update!(
        total_worked_days: [guide.total_worked_days - 1, 0].max
      )
    end
  end
end