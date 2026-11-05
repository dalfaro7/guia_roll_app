require "test_helper"

class BusesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      name: "Test User",
      email: "bus_test@example.com",
      password: "password123",
      password_confirmation: "password123"
    )

    sign_in @user

    @company = TransportCompany.create!(name: "Test Company")
    @bus = Bus.create!(
      transport_company: @company,
      capacity: 20,
      plate: "TEST-001",
      alias: "Test Bus",
      phone: "8888-8888"
    )
  end

  test "should get index" do
    get buses_url
    assert_response :success
    assert_select "table tbody tr", text: /20 pasajeros/
  end

  test "search finds a bus by plate and shows a clear empty state" do
    Bus.create!(transport_company: TransportCompany.create!(name: "Other company"), capacity: 13,
      plate: "OTHER-002", alias: "Other bus")

    get buses_url, params: { q: "test-001" }
    assert_response :success
    assert_select "table tbody tr", count: 1
    assert_select "table tbody tr", text: /Test Bus/

    get buses_url, params: { q: "unlisted" }
    assert_response :success
    assert_select "h3", "No se encontraron buses"
  end

  test "should get show" do
    get bus_url(@bus)
    assert_response :success
  end

  test "should get new" do
    get new_bus_url
    assert_response :success
  end

  test "new four by four defaults to internal fleet and allows company choice" do
    TransportCompany.create!(name: "AAA Internal", internal_fleet: true)
    internal = TransportCompany.create!(name: "ARC", internal_fleet: true)

    get new_bus_url, params: { vehicle_kind: "four_by_four" }

    assert_response :success
    assert_select "h1", "Agregar 4x4"
    assert_select "select[name='bus[vehicle_kind]'] option[value='four_by_four'][selected]"
    assert_select "select[name='bus[transport_company_id]'] option[value='#{internal.id}'][selected]"
    assert_select "select[name='bus[transport_company_id]'] option[value='#{@company.id}']"
  end

  test "should get edit" do
    get edit_bus_url(@bus)
    assert_response :success
  end

  test "reassigning a bus changes future trips and keeps past company and cost" do
    replacement = TransportCompany.create!(name: "Replacement Company")
    old_rate = @company.transport_rates.find_by!(location: "Balsa",
      vehicle_kind: "bus", size_category: "large")
    new_rate = replacement.transport_rates.find_by!(location: "Balsa",
      vehicle_kind: "bus", size_category: "large")
    old_rate.update!(amount_cents: 13_000)
    new_rate.update!(amount_cents: 17_000)
    past = WorkDay.create!(date: Date.current + 4.days, guides_requested: 0)
    past.update_columns(date: Date.current - 1.day)
    today = WorkDay.create!(date: Date.current, guides_requested: 0)
    future = WorkDay.create!(date: Date.current + 2.days, guides_requested: 0)
    past_trip = BusAssignment.create!(bus: @bus, work_day: past,
      location: "Balsa", seats_assigned: 10)
    today_trip = BusAssignment.create!(bus: @bus, work_day: today,
      location: "Balsa", seats_assigned: 10)
    future_trip = BusAssignment.create!(bus: @bus, work_day: future,
      location: "Balsa", seats_assigned: 10)

    patch bus_url(@bus), params: { bus: { transport_company_id: replacement.id } }

    assert_redirected_to buses_path
    assert_equal replacement.id, @bus.reload.transport_company_id
    [past_trip, today_trip].each do |trip|
      assert_equal @company.id, trip.reload.transport_company_snapshot_id
      assert_equal @company.name, trip.transport_company_name_snapshot
      assert_equal 13_000, trip.cost_cents
    end
    assert_equal replacement.id, future_trip.reload.transport_company_snapshot_id
    assert_equal replacement.name, future_trip.transport_company_name_snapshot
    assert_equal 17_000, future_trip.cost_cents
    assert AuditLog.exists?(action: "reassign_bus_company", auditable_id: @bus.id)

    get work_day_path(past)
    assert_response :success
    assert_select ".card-body > .border.rounded", text: /Test Company/
    get work_day_path(future)
    assert_response :success
    assert_select ".card-body > .border.rounded", text: /Replacement Company/

    another_day = WorkDay.create!(date: Date.current + 3.days, guides_requested: 0)
    next_trip = BusAssignment.create!(bus: @bus, work_day: another_day,
      location: "Balsa", seats_assigned: 10)
    assert_equal replacement.id, next_trip.transport_company_snapshot_id
    assert_equal 17_000, next_trip.cost_cents
  end

  test "moving a bus to internal fleet changes only future transport costs" do
    internal = TransportCompany.create!(name: "Internal Company", internal_fleet: true)
    old_day = WorkDay.create!(date: Date.current + 4.days, guides_requested: 0)
    old_day.update_columns(date: Date.current - 1.day)
    future = WorkDay.create!(date: Date.current + 2.days, guides_requested: 0)
    old_trip = BusAssignment.create!(bus: @bus, work_day: old_day,
      location: "Balsa", seats_assigned: 10)
    future_trip = BusAssignment.create!(bus: @bus, work_day: future,
      location: "Balsa", seats_assigned: 10)

    patch bus_url(@bus), params: { bus: { transport_company_id: internal.id } }

    assert_redirected_to buses_path
    assert_equal @company.id, old_trip.reload.transport_company_snapshot_id
    assert_equal false, old_trip.internal_fleet_snapshot
    assert_equal 12_000, old_trip.cost_cents
    assert_equal internal.id, future_trip.reload.transport_company_snapshot_id
    assert_equal true, future_trip.internal_fleet_snapshot
    assert_equal 0, future_trip.cost_cents
  end

  test "reassignment refuses an incompatible driver without changing trips" do
    replacement = TransportCompany.create!(name: "Different Company")
    future = WorkDay.create!(date: Date.current + 2.days, guides_requested: 0)
    driver = Driver.create!(name: "Old company driver", transport_company: @company)
    trip = BusAssignment.create!(bus: @bus, driver: driver,
      work_day: future, location: "Balsa", seats_assigned: 10)

    patch bus_url(@bus), params: { bus: { transport_company_id: replacement.id } }

    assert_response :unprocessable_entity
    assert_select ".alert-danger", text: /otra empresa/
    assert_equal @company.id, @bus.reload.transport_company_id
    assert_equal @company.id, trip.reload.transport_company_snapshot_id
    assert_equal 12_000, trip.cost_cents
    assert_not AuditLog.exists?(action: "reassign_bus_company", auditable_id: @bus.id)
  end

  test "direct model change cannot bypass the historical company safeguard" do
    day = WorkDay.create!(date: Date.current + 4.days, guides_requested: 0)
    day.update_columns(date: Date.current - 1.day)
    BusAssignment.create!(bus: @bus, work_day: day,
      location: "Balsa", seats_assigned: 10)
    replacement = TransportCompany.create!(name: "Direct Change Company")

    assert_not @bus.update(transport_company: replacement)
    assert_equal @company.id, @bus.reload.transport_company_id
  end

  test "invalid edits show the error and keep the entered details" do
    patch bus_url(@bus), params: { bus: { alias: "Bus principal", capacity: 0 } }

    assert_response :success
    assert_select ".alert-danger", text: /Capacidad/
    assert_select "input[name='bus[alias]'][value='Bus principal']"
  end
end
