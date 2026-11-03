require "test_helper"
require_relative "../../db/migrate/20261103000000_create_compensation_system"

class CompensationAccessTest < ActionDispatch::IntegrationTest
  setup do
    if CompensationRate.none?
      CompensationRate.insert_all!(
        CreateCompensationSystem::INITIAL_RATES.map do |code, cents|
          { code: code.to_s, amount_cents: cents,
            effective_at: Time.utc(2020, 1, 1),
            created_at: Time.current, updated_at: Time.current }
        end
      )
    end
    @day = WorkDay.create!(date: Date.current + 2.days, guides_requested: 0)
    @day.departures.create!(label: "Balsa", location: "Balsa",
      starts_at: Time.find_zone!("America/Costa_Rica").local(
        @day.date.year, @day.date.month, @day.date.day, 6))
  end

  def user(role)
    User.create!(name: "Test #{role}", email: "#{role}-compensation@example.com",
      password: "password123", role: role)
  end

  test "admin can open daily valuation and tariff pages" do
    sign_in user(:admin)
    get work_day_compensation_path(@day)
    assert_response :success
    assert_select "h1", /Valoración/
    get compensation_rates_path
    assert_response :success
    get compensation_profiles_path
    assert_response :success
    get drivers_path
    assert_response :success
    get compensation_reports_path
    assert_response :success
    get compensation_settlements_path
    assert_response :success

    guide = Guide.create!(name: "Statement guide", priority: 3,
      active: true, pay_category: "freelance_regular")
    @day.departures.first.compensation_assignments.create!(
      guide: guide, role_code: "river_guide")
    @day.departures.create!(label: "Sara clase 3", location: "Sara-3",
      starts_at: Time.find_zone!("America/Costa_Rica").local(
        @day.date.year, @day.date.month, @day.date.day, 10))
      .compensation_assignments.create!(guide: guide, role_code: "river_guide")
    Compensation::RepriceDay.call(@day)
    get work_day_compensation_path(@day)
    assert_response :success
    assert_select "h2", "Total diario por persona"
    assert_match(/85[,.]00/, response.body)
    settlement = CompensationSettlement.find_by!(guide: guide)
    get compensation_settlement_path(settlement)
    assert_response :success
    assert_select "td", text: /Balsa/
  end

  test "accounting sees valuation but cannot change a departure" do
    sign_in user(:contabilidad)
    get work_day_compensation_path(@day)
    assert_response :success
    patch work_day_departure_path(@day, @day.departures.first), params: {
      departure: { status: "canceled", starts_at_time: "06:00" }
    }
    assert_redirected_to root_path
    assert_equal "scheduled", @day.departures.first.reload.status
  end

  test "human resources cannot see economic data" do
    sign_in user(:recursos_humanos)
    get work_day_compensation_path(@day)
    assert_redirected_to root_path
    get compensation_settlements_path
    assert_redirected_to root_path
  end

  test "operator can designate a different principal photographer" do
    first_guide = Guide.create!(name: "Photo principal", priority: 3,
      active: true, pay_category: "freelance_regular")
    second_guide = Guide.create!(name: "Photo second", priority: 3,
      active: true, pay_category: "freelance_regular")
    departure = @day.departures.first
    first = departure.compensation_assignments.create!(guide: first_guide,
      role_code: "photographer", principal_photographer: true)
    second = departure.compensation_assignments.create!(guide: second_guide,
      role_code: "photographer")

    sign_in user(:operador)
    patch work_day_compensation_assignment_path(@day, second), params: {
      compensation_assignment: {
        role_code: "photographer", photo_task: "none", status: "planned",
        principal_photographer: "1", also_drives: "0", bus_guide: "0"
      }
    }
    assert_redirected_to work_day_compensation_path(@day)
    assert_not first.reload.principal_photographer?
    assert second.reload.principal_photographer?
    assert AuditLog.exists?(action: "transfer_principal_photographer",
      auditable_id: first.id)
  end

  test "after 18:00 only admin can correct a departure with a reason" do
    departure = @day.departures.first
    travel_to departure.starts_at + 12.hours + 1.minute do
      sign_in user(:operador)
      patch work_day_departure_path(@day, departure), params: {
        departure: { status: "canceled", starts_at_time: "06:00" }
      }
      assert_equal "scheduled", departure.reload.status

      sign_out :user
      sign_in user(:admin)
      patch work_day_departure_path(@day, departure), params: {
        departure: { status: "canceled", starts_at_time: "06:00" }
      }
      assert_equal "scheduled", departure.reload.status

      patch work_day_departure_path(@day, departure), params: {
        departure: { status: "canceled", starts_at_time: "06:00" },
        correction_reason: "Salida cancelada por operación"
      }
      assert_equal "canceled", departure.reload.status
      assert AuditLog.exists?(action: "update_departure", auditable_id: departure.id)
    end
  end
end
