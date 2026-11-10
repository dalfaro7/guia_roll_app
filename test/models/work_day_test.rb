require "test_helper"

class WorkDayTest < ActiveSupport::TestCase
  test "one guide covers Sara and PM as two independent outings" do
    guide = Guide.create!(name: "Guide on two outings", priority: 3,
      active: true, pay_category: "freelance_regular")
    day = WorkDay.create!(date: Date.current + 20.days,
      status: :generated, guides_requested: 2)
    day.location_slots.create!(location: "Sara-3&4")
    day.location_slots.create!(location: "PM")
    guide_day = day.guide_days.find_by!(guide: guide)
    guide_day.update!(status: :worked, location: "Sara-3&4",
      role_primary: "River Guide")
    sara = day.departures.find_or_create_by!(label: "Sara-3&4") do |departure|
      departure.location = "Sara-3&4"
      departure.starts_at = Departure.fixed_start_for(day.date, "Sara-3&4")
    end
    sara.compensation_assignments.find_or_create_by!(guide: guide) do |assignment|
      assignment.guide_day = guide_day
      assignment.role_code = "river_guide"
    end
    pm = day.departures.create!(label: "PM", location: "PM",
      starts_at: Departure.fixed_start_for(day.date, "PM"))
    pm.compensation_assignments.create!(guide: guide, role_code: "river_guide")

    roster = RollOutingRoster.new(day)
    assert_equal ["Sara-3&4", "PM"], roster.entries.map(&:location)
    assert_equal({ "Sara-3&4" => 1, "PM" => 1 }, roster.counts_by_section)
    assert_equal 2, day.assigned_roll_count
    assert_empty day.roll_coverage_errors
    assert_equal "Sara-3&4", guide_day.reload.location
    day.publish!
    assert day.reload.published?
  end

  test "a canceled payment row does not hide a worked guide day" do
    guide = Guide.create!(name: "Guide with corrected payment", priority: 3,
      active: true)
    day = WorkDay.create!(date: Date.current + 22.days, status: :generated)
    day.location_slots.create!(location: "Balsa")
    guide_day = day.guide_days.find_by!(guide: guide)
    guide_day.update!(status: :worked, location: "Balsa",
      role_primary: "River Guide")
    departure = day.departures.find_or_create_by!(label: "Balsa") do |outing|
      outing.location = "Balsa"
      outing.starts_at = Departure.fixed_start_for(day.date, "Balsa")
    end
    assignment = departure.compensation_assignments.find_or_create_by!(guide: guide) do |row|
      row.guide_day = guide_day
      row.role_code = "river_guide"
    end
    assignment.update!(status: "canceled")

    assert_equal ["Balsa"], RollOutingRoster.new(day).entries.map(&:location)
    assert_empty day.roll_coverage_errors
  end

  test "publication rejects two Sara assignments when PM needs one guide" do
    guides = 2.times.map do |index|
      Guide.create!(name: "Guide #{index} on Sara", priority: 3,
        active: true, pay_category: "freelance_regular")
    end
    day = WorkDay.create!(date: Date.current + 21.days,
      status: :generated, guides_requested: 2)
    day.location_slots.create!(location: "Sara-3&4")
    day.location_slots.create!(location: "PM")
    guides.each do |guide|
      day.guide_days.find_by!(guide: guide).update!(status: :worked,
        location: "Sara-3&4", role_primary: "River Guide")
    end

    assert_equal 2, day.assigned_roll_count
    assert_includes day.roll_coverage_errors, "Sara-3&4: 2 de 1 puestos cubiertos"
    assert_includes day.roll_coverage_errors, "PM: 0 de 1 puestos cubiertos"
    assert_raises(ActiveRecord::RecordInvalid) { day.publish! }
    assert day.reload.generated?
  end

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
