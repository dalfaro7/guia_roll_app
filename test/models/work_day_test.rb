require "test_helper"

class WorkDayTest < ActiveSupport::TestCase
  test "four by four spaces do not count as passenger seats" do
    company = TransportCompany.create!(name: "ARC Capacity Test", internal_fleet: true,
      vehicle_categories: %w[bus_small bus_large four_by_four])
    day = WorkDay.create!(date: Date.current + 12.days, guides_requested: 0)
    day.location_slots.create!(location: "Balsa", passengers: 18)
    bus = Bus.create!(alias: "Bus para pasajeros", plate: "PAX-15",
      capacity: 15, transport_company: company)
    four_by_four = Bus.create!(alias: "4x4 para guías", plate: "GUIDE-4",
      capacity: 4, vehicle_kind: "four_by_four", transport_company: company)
    BusAssignment.create!(bus: bus, work_day: day, location: "Balsa",
      seats_assigned: 10)
    BusAssignment.create!(bus: four_by_four, work_day: day, location: "Balsa",
      seats_assigned: 2)

    assert_equal 15, day.bus_capacity_for("Balsa")
    assert_equal(-3, day.seats_remaining_for("Balsa"))
    assert_equal 4, day.four_by_four_guide_capacity_for("Balsa")
    assert_equal 2, day.four_by_four_guide_spaces_remaining_for("Balsa")
  end
end
