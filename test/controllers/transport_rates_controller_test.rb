require "test_helper"

class TransportRatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: "Tarifas transporte", email: "transport-rates@example.test",
      password: "password123", role: :operador)
    sign_in @user
    TransportRate::LOCATIONS.product(TransportRate::CATEGORIES).each do |location, category|
      TransportRate.find_or_create_by!(location: location, size_category: category) do |rate|
        rate.amount_cents = 12_000
      end
    end
  end

  test "operator sees and updates the eight transport tariffs" do
    get transport_rates_path
    assert_response :success
    assert_select "h1", "Tarifario de transporte"
    assert_select "tbody tr", count: 8
    rate = TransportRate.find_by!(location: "Balsa", size_category: "small")
    patch transport_rate_path(rate), params: { transport_rate: { amount_usd: "147.50" } }
    assert_redirected_to transport_rates_path
    assert_equal 14_750, rate.reload.amount_cents
    assert AuditLog.exists?(action: "update_transport_rate", auditable_type: "TransportRate", auditable_id: rate.id)
  end

  test "accounting can view rates but cannot change them" do
    @user.update!(role: :contabilidad)
    get transport_rates_path
    assert_response :success
    assert_select "form[action^='/transport_rates/']", count: 0
    rate = TransportRate.first
    patch transport_rate_path(rate), params: { transport_rate: { amount_usd: "99.00" } }
    assert_redirected_to root_path
    assert_equal 12_000, rate.reload.amount_cents
  end
end
