class GuideDay < ApplicationRecord
  belongs_to :guide
  belongs_to :work_day
  belongs_to :modified_by, class_name: "User", optional: true

  enum :status, {
    worked: 0,
    standby: 1,
    day_off: 2,
    vacation: 3
  }

  validates :status, presence: true
  before_update :handle_manual_modification, if: :saved_change_to_status?

  private

def handle_manual_modification
  return unless manually_modified?

  work_day = self.work_day
  month = work_day.date.beginning_of_month

  old_status = status_before_last_save
  new_status = status

  return if old_status == new_status

  balance = MonthlyBalance.find_by(guide: guide, month: month)

  if old_status == "worked"
    balance&.decrement!(:worked_days)
    guide.decrement!(:total_worked_days)
  end

  if new_status == "worked"
    balance ||= MonthlyBalance.create!(
      guide: guide,
      month: month,
      worked_days: 0,
      balance: 0,
      bus_days: 0
    )

    balance.increment!(:worked_days)
    guide.increment!(:total_worked_days)
  end
end
end
