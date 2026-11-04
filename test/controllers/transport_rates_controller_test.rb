require "test_helper"

class TransportRatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: "Tarifas transporte", email: "transport-rates@example.test",
      password: "password123", role: :operador)
    sign_in @user
    @company = TransportCompany.create!(name: "Transportes Uno")
    @other_company = TransportCompany.create!(name: "Transportes Dos")
  end

  test "operator sees and updates one company without changing the other" do
    get transport_rates_path
    assert_response :success
    assert_select "h1", "Tarifario de transporte"
    assert_select "section h2", count: 2
    assert_select "tbody tr", count: 24
    rate = @company.transport_rates.find_by!(location: "Balsa", size_category: "small", vehicle_kind: "bus")
    other = @other_company.transport_rates.find_by!(location: "Balsa", size_category: "small", vehicle_kind: "bus")
    patch transport_rate_path(rate), params: { transport_rate: { amount_usd: "147.50" } }
    assert_redirected_to transport_rates_path
    assert_equal 14_750, rate.reload.amount_cents
    assert_equal 12_000, other.reload.amount_cents
    assert AuditLog.exists?(action: "update_transport_rate", auditable_type: "TransportRate", auditable_id: rate.id)
  end

  test "accounting can view rates but cannot change them" do
    @user.update!(role: :contabilidad)
    get transport_rates_path
    assert_response :success
    assert_select "form[action^='/transport_rates/']", count: 0
    rate = @company.transport_rates.first
    patch transport_rate_path(rate), params: { transport_rate: { amount_usd: "99.00" } }
    assert_redirected_to root_path
    assert_equal 12_000, rate.reload.amount_cents
  end
end
