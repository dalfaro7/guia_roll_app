class RoleResetService
  def initialize(work_day)
    @work_day = work_day
  end

  def call
    ActiveRecord::Base.transaction do
      restore_day_off_balances
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
      restore_day_off_balances
    end
  end

  private

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

  def clear_worked_assignments
    @work_day.guide_days.find_each do |guide_day|
      next if guide_day.day_off? || guide_day.vacation?

      guide_day.update!(
        status: :standby,
        status_note: nil,
        role_primary: nil,
        role_secondary: nil,
        location: nil,
        manually_modified: false,
        modified_by_id: nil,
        day_off_consumed: false
      )
    end
  end
end