require "test_helper"

class BusAssignmentTest < ActiveSupport::TestCase
  setup do
    @company = TransportCompany.create!(name: "Bus company test")
    @other_company = TransportCompany.create!(name: "Other company test")
    @bus = Bus.create!(alias: "Bus uno", plate: "ABC-100", capacity: 15,
      transport_company: @company)
    @work_day = WorkDay.create!(date: Date.current + 40.days, status: :draft,
      guides_requested: 0)
  end

  test "one bus can only be assigned once per day" do
    BusAssignment.create!(bus: @bus, work_day: @work_day, location: "Balsa", seats_assigned: 10)
    second = BusAssignment.new(bus: @bus, work_day: @work_day, location: "Sarapiqui", seats_assigned: 5)
    assert_not second.valid?
    assert_not_includes Bus.available_on(@work_day), @bus
  end

  test "driver is optional but must belong to the bus company" do
    assignment = BusAssignment.new(bus: @bus, work_day: @work_day,
      location: "Balsa", seats_assigned: 10)
    assert assignment.valid?
    assignment.driver = Driver.create!(name: "Otro chofer", phone: "555-1111",
      transport_company: @other_company)
    assert_not assignment.valid?
    assignment.driver = Driver.create!(name: "Chofer correcto", phone: "555-2222",
      transport_company: @company)
    assert assignment.valid?
  end

  test "bus cost starts at 120 dollars and accepts exact USD edits" do
    assignment = BusAssignment.create!(bus: @bus, work_day: @work_day,
      location: "Balsa", seats_assigned: 10)
    assert_equal 12_000, assignment.cost_cents
    assignment.update!(cost_usd: "135.50")
    assert_equal 13_550, assignment.reload.cost_cents
    assignment.cost_usd = "10.999"
    assert_not assignment.valid?
  end

  test "new assignment copies the matching tariff and keeps its snapshot" do
    rate = TransportRate.find_or_create_by!(location: "Balsa", size_category: "small") do |record|
      record.amount_cents = 12_000
    end
    rate.update!(amount_cents: 15_000)
    assignment = BusAssignment.create!(bus: @bus, work_day: @work_day,
      location: "Balsa", seats_assigned: 10)
    assert_equal 15_000, assignment.cost_cents
    rate.update!(amount_cents: 17_000)
    assert_equal 15_000, assignment.reload.cost_cents
  end

  test "tariff lookup distinguishes bus category and departure" do
    small_balsa = TransportRate.find_or_create_by!(location: "Balsa", size_category: "small") { |r| r.amount_cents = 12_000 }
    large_balsa = TransportRate.find_or_create_by!(location: "Balsa", size_category: "large") { |r| r.amount_cents = 12_000 }
    small_sara = TransportRate.find_or_create_by!(location: "Sara-3&4", size_category: "small") { |r| r.amount_cents = 12_000 }
    small_balsa.update!(amount_cents: 13_000)
    large_balsa.update!(amount_cents: 15_000)
    small_sara.update!(amount_cents: 17_000)
    large_bus = Bus.create!(alias: "Bus grande", plate: "ABC-200", capacity: 20,
      transport_company: @company)
    another_day = WorkDay.create!(date: @work_day.date + 1.day, status: :draft,
      guides_requested: 0)

    assert_equal 13_000, BusAssignment.create!(bus: @bus, work_day: @work_day,
      location: "Balsa", seats_assigned: 10).cost_cents
    assert_equal 15_000, BusAssignment.create!(bus: large_bus, work_day: @work_day,
      location: "Balsa", seats_assigned: 10).cost_cents
    assert_equal 17_000, BusAssignment.create!(bus: @bus, work_day: another_day,
      location: "Sara-3&4", seats_assigned: 10).cost_cents
  end

  test "capacity determines the allowed category" do
    @bus.capacity = 16
    assert_not @bus.valid?
    @bus.capacity = 20
    assert @bus.valid?
    assert_equal "large", @bus.size_category
  end
end
