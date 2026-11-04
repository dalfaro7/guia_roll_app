require "test_helper"
require_relative "../../db/migrate/20261103000000_create_compensation_system"

class FourByFourDriverPaymentsTest < ActiveSupport::TestCase
  setup do
    rates = CreateCompensationSystem::INITIAL_RATES.merge(driver_per_trip: 2_000)
    rates.each do |code, cents|
      next if CompensationRate.exists?(code: code.to_s)
      CompensationRate.insert!({ code: code.to_s, amount_cents: cents,
        effective_at: Time.utc(2020, 1, 1), created_at: Time.current,
        updated_at: Time.current })
    end
    unless CompensationDiscountRule.exists?(code: "second_sara")
      CompensationDiscountRule.insert!({ code: "second_sara", percent: 20,
        effective_at: Time.utc(2020, 1, 1), created_at: Time.current,
        updated_at: Time.current })
    end
    @day = WorkDay.create!(date: Date.current + 5.days, guides_requested: 0)
    @arc = TransportCompany.create!(name: "ARC", internal_fleet: true)
    @external = TransportCompany.create!(name: "Viajes del Arenal")
    @arc_4x4 = Bus.create!(alias: "ARC 4x4", plate: "ARC-4X4",
      capacity: 4, transport_company: @arc, vehicle_kind: "four_by_four")
    @external_4x4 = Bus.create!(alias: "Externo 4x4", plate: "EXT-4X4",
      capacity: 4, transport_company: @external, vehicle_kind: "four_by_four")
  end

  def assign(bus:, driver:, location:, variant: nil)
    BusAssignment.create!(bus: bus, driver: driver, work_day: @day,
      location: location, outing_variant: variant, seats_assigned: 2)
  end

  test "Adriana receives twenty dollars for Sara four and sixteen for PM" do
    adriana = Driver.create!(name: "Adriana", payment_mode: "per_trip")
    first = assign(bus: @arc_4x4, driver: adriana,
      location: "Sara-3&4", variant: "Sara-4")
    second = assign(bus: @arc_4x4, driver: adriana, location: "PM")

    assert_equal 0, first.cost_cents
    assert_equal 2_000, first.driver_payment_cents
    assert_equal 1_600, second.driver_payment_cents
    quote = Compensation::DriverPaymentQuote.call(work_day: @day,
      bus: @arc_4x4, driver: adriana, location: "PM")
    assert_equal 1_600, quote[:driver_payment_cents]
    assert_equal 0, quote[:transport_cost_cents]
    assert_equal 20, second.compensation_assignment.compensation_lines
      .find_by!(code: "driver_per_trip").discount_percent
    assert_equal 2, BusAssignment.where(bus: @arc_4x4, work_day: @day).count
  end

  test "Asdrubal receives forty five dollars once per day" do
    asdrubal = Driver.create!(name: "Asdrúbal", transport_company: @arc,
      payment_mode: "daily_hg")
    first = assign(bus: @arc_4x4, driver: asdrubal,
      location: "Sara-3&4", variant: "Sara-4")
    second = assign(bus: @arc_4x4, driver: asdrubal, location: "PM")

    assert_equal 4_500, first.driver_payment_cents
    assert_equal 0, second.driver_payment_cents
    assert first.update(cost_usd: "0.00")
    assert_equal 1, CompensationAssignment.where(driver: asdrubal).active.count
  end

  test "Mario receives forty dollars for ARC but zero direct payment for an external company" do
    mario = Driver.create!(name: "Mario", payment_mode: "round_trip")
    own = assign(bus: @arc_4x4, driver: mario, location: "Balsa")
    assert_equal 4_000, own.driver_payment_cents

    other_day = WorkDay.create!(date: @day.date + 1.day, guides_requested: 0)
    external = BusAssignment.create!(bus: @external_4x4, driver: mario,
      work_day: other_day, location: "Balsa", seats_assigned: 2)
    assert_equal 0, external.driver_payment_cents
    assert_operator external.cost_cents, :>, 0
    assert_nil external.compensation_assignment
    @external.transport_rates.find_by!(location: "Balsa",
      vehicle_kind: "four_by_four", size_category: "small")
      .update!(amount_cents: 18_000)
    assert_equal 12_000, external.reload.cost_cents
    quote = Compensation::DriverPaymentQuote.call(work_day: other_day,
      bus: @external_4x4, driver: mario, location: "Balsa")
    assert_equal 0, quote[:driver_payment_cents]
  end

  test "external four by four uses its own company tariff rather than a small bus tariff" do
    @external.transport_rates.find_by!(location: "Balsa",
      vehicle_kind: "four_by_four", size_category: "small")
      .update!(amount_cents: 18_500)
    small_bus = Bus.create!(alias: "Bus pequeño", plate: "BUS-15", capacity: 15,
      transport_company: @external)
    four_by_four_assignment = assign(bus: @external_4x4, driver: nil,
      location: "Balsa")
    bus_assignment = assign(bus: small_bus, driver: nil, location: "Balsa")

    assert_equal 18_500, four_by_four_assignment.cost_cents
    assert_equal 12_000, bus_assignment.cost_cents
    assert_equal false, four_by_four_assignment.internal_fleet_snapshot
    assert_not small_bus.update(vehicle_kind: "four_by_four")
  end

  test "four by four cannot repeat unless the first trip is Sara four and second is PM" do
    driver = Driver.create!(name: "Chofer", payment_mode: "none")
    first = assign(bus: @arc_4x4, driver: driver,
      location: "Sara-3&4", variant: "Sara-3")
    assert_not VehicleAvailability.available?(bus: @arc_4x4,
      work_day: @day, location: "PM")
    assert_raises(ActiveRecord::RecordInvalid) do
      assign(bus: @arc_4x4, driver: driver, location: "PM")
    end
    first.destroy!
    assign(bus: @arc_4x4, driver: driver, location: "Balsa")
    assert_raises(ActiveRecord::RecordInvalid) do
      assign(bus: @arc_4x4, driver: driver, location: "PM")
    end
  end

  test "same driver cannot be assigned to two different vehicles on one day" do
    driver = Driver.create!(name: "Chofer ocupado", payment_mode: "none")
    assign(bus: @arc_4x4, driver: driver, location: "Balsa")
    assert_raises(ActiveRecord::RecordInvalid) do
      assign(bus: @external_4x4, driver: driver, location: "PM")
    end
  end

  test "Sara four requires a class and a second PM trip keeps the same driver" do
    first_driver = Driver.create!(name: "Primero", payment_mode: "per_trip")
    second_driver = Driver.create!(name: "Segundo", payment_mode: "per_trip")
    assert_raises(ActiveRecord::RecordInvalid) do
      assign(bus: @arc_4x4, driver: first_driver, location: "Sara-3&4")
    end
    first = assign(bus: @arc_4x4, driver: first_driver,
      location: "Sara-3&4", variant: "Sara-4")
    assert_raises(ActiveRecord::RecordInvalid) do
      assign(bus: @arc_4x4, driver: nil, location: "PM")
    end
    assert_raises(ActiveRecord::RecordInvalid) do
      assign(bus: @arc_4x4, driver: second_driver, location: "PM")
    end
    pm = assign(bus: @arc_4x4, driver: first_driver, location: "PM")
    assert_raises(ActiveRecord::RecordNotDestroyed) { first.destroy! }
    pm.destroy!
    first.destroy!
    assert_equal 0, first.compensation_assignment.reload.total_cents
  end
end
