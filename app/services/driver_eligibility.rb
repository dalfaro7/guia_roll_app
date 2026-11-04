class DriverEligibility
  def self.available?(driver:, bus:, work_day:, location:, outing_variant: nil,
    excluding: nil)
    assignments = BusAssignment.where(driver_id: driver.id,
      work_day_id: work_day.id)
    assignments = assignments.where.not(id: excluding.id) if excluding&.persisted?
    previous = assignments.order(:id).to_a
    return true if previous.empty?
    return false unless bus.four_by_four? && location == "PM" && previous.one?

    first = previous.first
    first.bus_id == bus.id && first.location == "Sara-3&4" &&
      first.outing_variant == "Sara-4"
  end
end
