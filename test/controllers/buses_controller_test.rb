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

  test "invalid edits show the error and keep the entered details" do
    patch bus_url(@bus), params: { bus: { alias: "Bus principal", capacity: 0 } }

    assert_response :success
    assert_select ".alert-danger", text: /Capacidad/
    assert_select "input[name='bus[alias]'][value='Bus principal']"
  end
end
