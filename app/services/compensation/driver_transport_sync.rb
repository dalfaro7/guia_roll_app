module Compensation
  class DriverTransportSync
    ROLE_BY_MODE = {
      "per_trip" => "driver_per_trip",
      "daily_hg" => "driver_hg",
      "round_trip" => "driver_la_fortuna"
    }.freeze

    def self.call(bus_assignment)
      driver = bus_assignment.driver
      work_day = bus_assignment.work_day
      return unless driver && bus_assignment.internal_fleet_snapshot?
      return unless Compensation::EditWindow.applicable?(work_day)

      role = ROLE_BY_MODE[driver.payment_mode]
      return unless role

      existing = CompensationAssignment.joins(:departure)
        .where(departures: { work_day_id: work_day.id }, driver_id: driver.id)
        .active
      return if driver.payment_mode != "per_trip" && existing.exists?

      departure = work_day.departures.find_or_create_by!(label: bus_assignment.location) do |record|
        record.location = bus_assignment.location
        record.starts_at = Departure.fixed_start_for(work_day.date, record.location)
      end
      if existing.where(departure_id: departure.id).exists?
        bus_assignment.errors.add(:driver, "ya tiene una valoración para esta salida")
        raise ActiveRecord::RecordInvalid, bus_assignment
      end

      assignment = departure.compensation_assignments.find_by(driver_id: driver.id)
      if assignment
        if assignment.status == "canceled" && assignment.source == "automatic" &&
            assignment.updated_by_id.nil? && assignment.bus_assignment.nil?
          assignment.update!(status: "planned", role_code: role)
        else
          bus_assignment.errors.add(:driver, "ya tiene una valoración registrada para esta salida")
          raise ActiveRecord::RecordInvalid, bus_assignment
        end
      else
        assignment = departure.compensation_assignments.create!(
          driver: driver, role_code: role, status: "planned", source: "automatic"
        )
      end
      bus_assignment.update_column(:compensation_assignment_id, assignment.id)
      Compensation::RepriceDay.call(work_day, driver: driver)
    end
  end
end
