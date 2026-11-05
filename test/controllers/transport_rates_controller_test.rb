require "test_helper"

class TransportRatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: "Tarifas transporte", email: "transport-rates@example.test",
      password: "password123", role: :operador)
    sign_in @user
    @company = TransportCompany.create!(name: "Transportes Uno")
    @other_company = TransportCompany.create!(name: "Transportes Dos")
  end

  def rate_values_for(company)
    company.transport_rates
      .select { |rate| company.offers_vehicle_category?(
        vehicle_kind: rate.vehicle_kind, size_category: rate.size_category) }
      .index_by { |rate| rate.id.to_s }.transform_values(&:amount_usd)
  end

  test "filter shows one company and one bulk update changes only its rates" do
    get transport_rates_path
    assert_response :success
    assert_select "h1", "Tarifario de transporte"
    assert_select "section h2", count: 2
    assert_select "details[name='transport-rate-companies']", count: 2
    assert_select "details[open]", count: 1
    assert_select "tbody tr", count: 16
    assert_select "select[name='transport_company_id'] option", count: 3
    assert_select "a", text: "Editar tarifas de esta empresa", count: 0
    assert_select "form[action='#{bulk_update_transport_rates_path}']", count: 0

    get transport_rates_path(transport_company_id: @company.id)
    assert_response :success
    assert_select "section h2", text: @company.name, count: 1
    assert_select "details[name='transport-rate-companies'][open]", count: 1
    assert_select "tbody tr", count: 8
    assert_select "a[href='#{transport_rates_path(transport_company_id: @company.id, edit: 1)}']", text: "Editar tarifas de esta empresa"

    get transport_rates_path(transport_company_id: @company.id, edit: 1)
    assert_response :success
    assert_select "form[action='#{bulk_update_transport_rates_path}']", count: 1
    assert_select "input[name='transport_company_id'][value='#{@company.id}']"
    assert_select "input[name^='rates[']", count: 8
    assert_select "input[type='submit'][value='Actualizar tarifas de #{@company.name}']", count: 1

    first = @company.transport_rates.find_by!(location: "Balsa", size_category: "small", vehicle_kind: "bus")
    second = @company.transport_rates.find_by!(location: "PM", size_category: "large", vehicle_kind: "bus")
    untouched = @other_company.transport_rates.find_by!(location: "PM", size_category: "large", vehicle_kind: "bus")
    values = rate_values_for(@company).merge(first.id.to_s => "147.50", second.id.to_s => "165.00")
    assert_difference "AuditLog.where(action: 'update_transport_rate').count", 2 do
      patch bulk_update_transport_rates_path, params: { transport_company_id: @company.id, rates: values }
    end
    assert_redirected_to transport_rates_path(transport_company_id: @company.id)
    assert_equal 14_750, first.reload.amount_cents
    assert_equal 16_500, second.reload.amount_cents
    assert_equal 12_000, untouched.reload.amount_cents
  end

  test "invalid, incomplete or cross-company bulk edit changes nothing" do
    first = @company.transport_rates.find_by!(location: "Balsa", size_category: "small", vehicle_kind: "bus")
    other = @other_company.transport_rates.find_by!(location: "Balsa", size_category: "small", vehicle_kind: "bus")
    values = rate_values_for(@company).merge(first.id.to_s => "bad")
    assert_no_difference "AuditLog.count" do
      patch bulk_update_transport_rates_path,
        params: { transport_company_id: @company.id, rates: values }
    end
    assert_response :unprocessable_entity
    assert_select "input[name='rates[#{first.id}]'][value='bad']"
    assert_equal 12_000, first.reload.amount_cents

    patch bulk_update_transport_rates_path,
      params: { transport_company_id: @company.id,
        rates: rate_values_for(@company).except(first.id.to_s) }
    assert_response :unprocessable_entity
    assert_equal 12_000, first.reload.amount_cents

    patch bulk_update_transport_rates_path,
      params: { transport_company_id: @company.id,
        rates: rate_values_for(@company).merge(other.id.to_s => "150.00") }
    assert_response :unprocessable_entity
    assert_equal 12_000, first.reload.amount_cents
    assert_equal 12_000, other.reload.amount_cents

    patch bulk_update_transport_rates_path, params: { rates: rate_values_for(@company) }
    assert_response :unprocessable_entity
  end

  test "accounting can filter and view rates but cannot edit them" do
    @user.update!(role: :contabilidad)
    get transport_rates_path(transport_company_id: @company.id)
    assert_response :success
    assert_select "section h2", count: 1
    assert_select "a", text: "Editar tarifas de esta empresa", count: 0
    get transport_rates_path(transport_company_id: @company.id, edit: 1)
    assert_response :success
    assert_select "form[action='#{bulk_update_transport_rates_path}']", count: 0
    patch bulk_update_transport_rates_path,
      params: { transport_company_id: @company.id, rates: rate_values_for(@company) }
    assert_redirected_to root_path
  end
end
