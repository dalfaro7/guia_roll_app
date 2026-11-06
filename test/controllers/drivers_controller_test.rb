require "test_helper"

class DriversControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(name: "Transport admin", email: "drivers-admin@example.test",
      password: "password123", role: :admin)
    sign_in @admin
  end

  test "admin can delete a driver without history after a visible confirmation" do
    driver = Driver.create!(name: "Mario", payment_mode: "none")

    get drivers_url
    assert_response :success
    assert_select "form[action='#{driver_path(driver)}'][data-turbo-confirm*='¿Estás seguro']"

    assert_difference("Driver.count", -1) do
      delete driver_url(driver)
    end

    assert_redirected_to drivers_url
    assert AuditLog.exists?(action: "destroy_driver", auditable_type: "Driver",
      auditable_id: driver.id)
  end

  test "driver with a trip cannot be deleted or erased from its history" do
    company = TransportCompany.create!(name: "ARC Drivers Test", internal_fleet: true)
    bus = Bus.create!(alias: "Bus de prueba", plate: "TEST-DRIVER-1", capacity: 15,
      transport_company: company)
    driver = Driver.create!(name: "Mario", transport_company: company,
      payment_mode: "none")
    day = WorkDay.create!(date: Date.current + 90.days, guides_requested: 0)
    assignment = BusAssignment.create!(bus: bus, driver: driver, work_day: day,
      location: "Balsa", seats_assigned: 1)

    assert_no_difference("Driver.count") do
      delete driver_url(driver)
    end

    assert_redirected_to drivers_url
    assert_equal driver, assignment.reload.driver
    assert_match(/tiene viajes o pagos registrados/, flash[:alert])
  end

  test "operator can create update and delete a driver without history" do
    operator = User.create!(name: "Driver operator", email: "driver-operator@example.test",
      password: "password123", role: :operador)
    sign_out @admin
    sign_in operator

    get drivers_url
    assert_response :success
    assert_select "nav a[href='#{drivers_path}']", text: "Choferes"

    assert_difference("Driver.count", 1) do
      post drivers_url, params: { driver: { name: "Nuevo chofer", payment_mode: "none" } }
    end
    driver = Driver.find_by!(name: "Nuevo chofer")
    patch driver_url(driver), params: { driver: { name: "Chofer actualizado", payment_mode: "per_trip" } }
    assert_redirected_to drivers_url
    assert_equal "Chofer actualizado", driver.reload.name
    assert_equal "per_trip", driver.payment_mode

    assert_difference("Driver.count", -1) { delete driver_url(driver) }
    assert_redirected_to drivers_url
  end

  test "accounting cannot manage drivers" do
    accounting = User.create!(name: "Driver accounting", email: "driver-accounting@example.test",
      password: "password123", role: :contabilidad)
    sign_out @admin
    sign_in accounting

    get drivers_url
    assert_redirected_to root_path
    assert_no_difference("Driver.count") do
      post drivers_url, params: { driver: { name: "No autorizado", payment_mode: "none" } }
    end
    assert_redirected_to root_path
  end
end
