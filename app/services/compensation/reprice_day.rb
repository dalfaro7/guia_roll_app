module Compensation
  class RepriceDay
    def self.call(work_day, guide: nil, driver: nil)
      scope = CompensationAssignment
        .joins(:departure)
        .where(departures: { work_day_id: work_day.id })
        .includes(:departure, :guide, :driver)

      scope = scope.where(guide: guide) if guide
      scope = scope.where(driver: driver) if driver

      scope.order("departures.starts_at ASC, departures.id ASC").each do |assignment|
        Compensation::Calculator.call(assignment)
      end

      Compensation::SettlementService.refresh_for(work_day)
    end
  end
end
