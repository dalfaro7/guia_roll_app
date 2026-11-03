class CompensationCloseDueDaysJob < ApplicationJob
  queue_as :default

  def perform
    now = Time.current
    Compensation::ScheduleSync.backfill_future!(now: now)
    local_now = now.in_time_zone("America/Costa_Rica")
    due = Departure.joins(:work_day)
      .where(closed_at: nil)
      .where("work_days.date < ?", local_now.hour >= 18 ? local_now.to_date + 1.day : local_now.to_date)
      .includes(:work_day)

    due.find_each do |departure|
      departure.with_lock do
        next if departure.closed?

        if departure.status == "canceled"
          departure.compensation_assignments.where(status: "planned")
            .update_all(status: "canceled", updated_at: now)
        else
          departure.compensation_assignments.where(status: "planned")
            .update_all(status: "performed", updated_at: now)
          departure.update!(status: "completed", closed_at: now)
        end
        departure.update!(closed_at: now) if departure.closed_at.blank?
      end
      Compensation::RepriceDay.call(departure.work_day)
    end

    Compensation::SettlementService.close_due!(now: now)
  end
end
