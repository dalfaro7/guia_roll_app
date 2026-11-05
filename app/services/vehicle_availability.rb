class VehicleAvailability
  def self.for(work_day:, location:)
    Bus.includes(:transport_company).order(:alias).select do |bus|
      available?(bus: bus, work_day: work_day, location: location)
    end
  end

  def self.available?(bus:, work_day:, location:, outing_variant: nil,
    driver: nil, excluding: nil, require_matching_driver: false)
    return false unless bus.transport_company.offers_vehicle_category?(
      vehicle_kind: bus.vehicle_kind, size_category: bus.size_category)

    assignments = BusAssignment.where(bus_id: bus.id, work_day_id: work_day.id)
    assignments = assignments.where.not(id: excluding.id) if excluding&.persisted?
    previous = assignments.order(:id).to_a
    return true if previous.empty?
    return false unless bus.four_by_four? && location == "PM" && previous.one?

    first = previous.first
    first.location == "Sara-3&4" && first.outing_variant == "Sara-4" &&
      first.driver_id.present? &&
      ((!require_matching_driver && driver.nil?) || first.driver_id == driver&.id)
  end
end
