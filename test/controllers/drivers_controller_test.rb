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
end
