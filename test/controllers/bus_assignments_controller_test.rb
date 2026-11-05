require "test_helper"

class BusAssignmentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      name: "Test User",
      email: "busassignments@test.com",
      password: "password123",
      password_confirmation: "password123",
      role: :operador
    )

    sign_in @user

    @company = TransportCompany.create!(name: "Test Company")
    @bus = Bus.create!(
      transport_company: @company,
      capacity: 20,
      plate: "TEST-001",
      alias: "Bus Test",
      phone: "88888888"
    )

    @work_day = WorkDay.new(
      date: Date.current,
      status: :draft,
      guides_requested: 0
    )

    @work_day.save!(validate: false)

    @assignment = BusAssignment.create!(
      bus: @bus,
      work_day: @work_day,
      location: "Balsa",
      seats_assigned: 10
    )
  end

  test "should create bus assignment" do
    second_bus = Bus.create!(
      transport_company: TransportCompany.create!(name: "Second Company"),
      capacity: 25,
      plate: "TEST-002",
      alias: "Bus Test 2",
      phone: "87777777"
    )

    assert_difference("BusAssignment.count", 1) do
      post bus_assignments_path,
           params: {
             bus_assignment: {
               bus_id: second_bus.id,
               work_day_id: @work_day.id,
               location: "Sara-3&4",
               seats_assigned: 12
             }
           }
    end

    assert_response :redirect
    assert_equal 12_000, BusAssignment.order(:id).last.cost_cents
  end

  test "rejects a driver from another company" do
    other_company = TransportCompany.create!(name: "Different Company")
    driver = Driver.create!(name: "Other driver", phone: "555-9999",
      transport_company: other_company)
    second_bus = Bus.create!(alias: "Second bus", plate: "SECOND-33", capacity: 20,
      transport_company: @company)

    assert_no_difference("BusAssignment.count") do
      post bus_assignments_path, params: { bus_assignment: {
        bus_id: second_bus.id, driver_id: driver.id, work_day_id: @work_day.id,
        location: "Balsa", seats_assigned: 10
      } }
    end
    assert_redirected_to work_day_path(@work_day)
  end

  test "assigned bus is absent from every departure selector and availability response" do
    second_bus = Bus.create!(transport_company: @company, capacity: 13,
      plate: "TEST-AVAILABLE", alias: "Available bus")

    get work_day_path(@work_day)
    assert_response :success
    assert_select "select[name='bus_assignment[bus_id]']", count: 4
    assert_select "select[name='bus_assignment[bus_id]'] option[value='#{@bus.id}']", count: 0
    assert_select "select[name='bus_assignment[bus_id]'] option[value='#{second_bus.id}']", count: 4

    get available_buses_work_day_path(@work_day)
    assert_response :success
    assert_equal [second_bus.id], response.parsed_body.fetch("buses").map { |bus| bus.fetch("id") }

    BusAssignment.create!(bus: second_bus, work_day: @work_day,
      location: "PM", seats_assigned: 2)
    get available_buses_work_day_path(@work_day)
    assert_empty response.parsed_body.fetch("buses")
  end

  test "four by four used in Sara four is offered for PM with its same driver" do
    @company.update!(vehicle_categories: @company.vehicle_categories + ["four_by_four"])
    vehicle = Bus.create!(transport_company: @company, capacity: 4,
      plate: "4X4-1", alias: "4x4", vehicle_kind: "four_by_four")
    driver = Driver.create!(name: "Chofer freelance")
    BusAssignment.create!(bus: vehicle, driver: driver, work_day: @work_day,
      location: "Sara-3&4", outing_variant: "Sara-4", seats_assigned: 2)

    get available_buses_work_day_path(@work_day), params: { location: "PM" }
    assert_response :success
    option = response.parsed_body.fetch("buses").find { |bus| bus.fetch("id") == vehicle.id }
    assert_equal driver.id, option.fetch("required_driver_id")

    get available_buses_work_day_path(@work_day), params: { location: "Balsa" }
    assert_not_includes response.parsed_body.fetch("buses").map { |bus| bus.fetch("id") }, vehicle.id

    get work_day_path(@work_day)
    assert_response :success
    assert_select "form[data-controller='bus-driver'] input[name='bus_assignment[location]'][value='PM']"
    assert_select "select[name='bus_assignment[bus_id]'] option[value='#{vehicle.id}'][data-required-driver-id='#{driver.id}']"
  end

  test "operator can apply a negotiated adjustment without changing the tariff" do
    @work_day.update_columns(date: Date.current + 2.days)
    rate = @company.transport_rates.find_by!(location: "Balsa", vehicle_kind: "bus",
      size_category: "large")
    assert_equal 12_000, @assignment.base_cost_cents
    assert_difference "AuditLog.where(action: 'update_bus_cost').count", 1 do
      patch bus_assignment_path(@assignment), params: {
        bus_assignment: { discount_usd: "25.75", discount_reason: "Bajo margen, acordado con proveedor" }
      }
    end
    assert_redirected_to work_day_path(@work_day)
    assert_equal 12_000, @assignment.reload.base_cost_cents
    assert_equal 2_575, @assignment.discount_cents
    assert_equal 9_425, @assignment.cost_cents
    assert_equal 12_000, rate.reload.amount_cents
    log = AuditLog.where(action: "update_bus_cost", auditable_id: @assignment.id).last
    assert_equal 12_000, log.metadata.fetch("base_cost_cents")
    assert_equal 2_575, log.metadata.fetch("after_discount_cents")
    assert_equal "Bajo margen, acordado con proveedor", log.metadata.fetch("discount_reason")
    get work_day_path(@work_day)
    assert_response :success
    assert_select "details", text: /Costo acordado:.*\$94\.25/
  end

  test "operator cannot adjust more than the base tariff or omit the agreement reason" do
    @work_day.update_columns(date: Date.current + 2.days)
    assert_no_difference "AuditLog.where(action: 'update_bus_cost').count" do
      patch bus_assignment_path(@assignment), params: {
        bus_assignment: { discount_usd: "120.01", discount_reason: "Solicitado" }
      }
    end
    assert_redirected_to work_day_path(@work_day)
    assert_equal 12_000, @assignment.reload.cost_cents
    assert_equal 0, @assignment.discount_cents

    patch bus_assignment_path(@assignment), params: {
      bus_assignment: { discount_usd: "20.00", discount_reason: "" }
    }
    assert_redirected_to work_day_path(@work_day)
    assert_equal 12_000, @assignment.reload.cost_cents

    patch bus_assignment_path(@assignment), params: {
      bus_assignment: { cost_usd: "200.00", discount_reason: "Intento sin ajuste" }
    }
    assert_redirected_to work_day_path(@work_day)
    assert_equal 12_000, @assignment.reload.cost_cents
  end

  test "cost details stay behind a disclosure on the operation screen" do
    get work_day_path(@work_day)
    assert_response :success
    assert_select "details summary", text: "Ver costo y pago del chofer"
    assert_select "form[action='#{bus_assignment_path(@assignment)}'] input[name='bus_assignment[discount_usd]'][max='120.0']"
    assert_select "form[action='#{bus_assignment_path(@assignment)}'] input[name='bus_assignment[discount_reason]']"
  end

  test "accounting can see but not edit bus cost" do
    @user.update!(role: :contabilidad)
    get work_day_path(@work_day)
    assert_response :success
    assert_select "details summary", text: "Ver costo y pago del chofer"
    assert_select "form[action='#{bus_assignment_path(@assignment)}'] input[name='bus_assignment[discount_usd]']", count: 0
    assert_select "form[action='#{bus_assignment_path(@assignment)}'] input[name='bus_assignment[discount_reason]']", count: 0
    patch bus_assignment_path(@assignment), params: { bus_assignment: { discount_usd: "15.00", discount_reason: "Test" } }
    assert_redirected_to root_path
    assert_equal 12_000, @assignment.reload.cost_cents
  end

  test "should destroy bus assignment" do
    assert_difference("BusAssignment.count", -1) do
      delete bus_assignment_path(@assignment)
    end

    assert_redirected_to work_day_path(@work_day)
  end
end