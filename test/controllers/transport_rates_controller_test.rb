require "test_helper"

class TransportRatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: "Tarifas transporte", email: "transport-rates@example.test",
      password: "password123", role: :operador)
    sign_in @user
    @company = TransportCompany.create!(name: "Transportes Uno")
    @other_company = TransportCompany.create!(name: "Transportes Dos")
  end

  def all_rate_values
    TransportRate.includes(:transport_company).order(:id)
      .select { |rate| rate.transport_company.offers_vehicle_category?(
        vehicle_kind: rate.vehicle_kind, size_category: rate.size_category) }
      .index_by { |rate| rate.id.to_s }.transform_values(&:amount_usd)
  end

  test "one button opens bulk edit and one form saves rates for different companies" do
    get transport_rates_path
    assert_response :success
    assert_select "h1", "Tarifario de transporte"
    assert_select "section h2", count: 2
    assert_select "tbody tr", count: 16
    assert_select "a[href='#{transport_rates_path(edit: 1)}']", text: "Editar todas las tarifas"
    assert_select "form[action^='/transport_rates/']", count: 0

    get transport_rates_path(edit: 1)
    assert_response :success
    assert_select "form[action='#{bulk_update_transport_rates_path}']", count: 1
    assert_select "input[name^='rates[']", count: 16
    assert_select "input[type='submit'][value='Guardar todas las tarifas']", count: 1

    first = @company.transport_rates.find_by!(location: "Balsa", size_category: "small", vehicle_kind: "bus")
    second = @other_company.transport_rates.find_by!(location: "PM", size_category: "large", vehicle_kind: "bus")
    values = all_rate_values.merge(first.id.to_s => "147.50", second.id.to_s => "165.00")
    assert_difference "AuditLog.where(action: 'update_transport_rate').count", 2 do
      patch bulk_update_transport_rates_path, params: { rates: values }
    end
    assert_redirected_to transport_rates_path
    assert_equal 14_750, first.reload.amount_cents
    assert_equal 16_500, second.reload.amount_cents
    assert_equal 12_000, @company.transport_rates.find_by!(location: "PM", size_category: "large", vehicle_kind: "bus").reload.amount_cents
  end

  test "invalid or incomplete bulk edit changes nothing" do
    first = @company.transport_rates.first
    second = @other_company.transport_rates.first
    values = all_rate_values.merge(first.id.to_s => "150.00", second.id.to_s => "bad")
    assert_no_difference "AuditLog.count" do
      patch bulk_update_transport_rates_path, params: { rates: values }
    end
    assert_response :unprocessable_entity
    assert_select "input[name='rates[#{first.id}]'][value='150.00']"
    assert_select "input[name='rates[#{second.id}]'][value='bad']"
    assert_equal 12_000, first.reload.amount_cents
    assert_equal 12_000, second.reload.amount_cents

    patch bulk_update_transport_rates_path,
      params: { rates: all_rate_values.except(first.id.to_s) }
    assert_response :unprocessable_entity
    assert_equal 12_000, second.reload.amount_cents
  end

  test "accounting can view rates but cannot edit them" do
    @user.update!(role: :contabilidad)
    get transport_rates_path
    assert_response :success
    assert_select "a", text: "Editar todas las tarifas", count: 0
    get transport_rates_path(edit: 1)
    assert_response :success
    assert_select "form[action='#{bulk_update_transport_rates_path}']", count: 0
    patch bulk_update_transport_rates_path,
      params: { rates: all_rate_values }
    assert_redirected_to root_path
  end
end
