require "test_helper"

class TransportCompaniesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(name: "Transport admin", email: "transport-admin@example.test",
      password: "password123", role: :admin)
    sign_in @admin
  end

  test "admin creates a company and sees it listed" do
    assert_difference("TransportCompany.count", 1) do
      post transport_companies_url, params: { transport_company: { name: "  Nueva Empresa  " } }
    end
    assert_redirected_to transport_companies_url
    assert_equal "Nueva Empresa", TransportCompany.order(:id).last.name
    get transport_companies_url
    assert_response :success
    assert_select "h1", "Empresas de transporte"
  end

  test "admin can enable or remove vehicle categories for a provider" do
    company = TransportCompany.create!(name: "Transportes Memo Test")
    assert_equal %w[bus_small bus_large], company.vehicle_categories
    assert_not company.offers_vehicle_category?(vehicle_kind: "four_by_four",
      size_category: "small")

    patch transport_company_url(company), params: { transport_company: {
      name: company.name, internal_fleet: "0",
      vehicle_categories: %w[bus_large four_by_four]
    } }
    assert_redirected_to transport_companies_url
    assert_equal %w[bus_large four_by_four], company.reload.vehicle_categories

    patch transport_company_url(company), params: { transport_company: {
      name: company.name, internal_fleet: "0", vehicle_categories: ["bus_large"]
    } }
    assert_redirected_to transport_companies_url
    assert_equal ["bus_large"], company.reload.vehicle_categories
  end

  test "admin can register a company driver or freelance with phone pending" do
    company = TransportCompany.create!(name: "ARC Test")
    get drivers_url
    assert_response :success
    assert_select "select[name='driver[transport_company_id]']"
    assert_difference("Driver.count", 1) do
      post drivers_url, params: { driver: { name: "Chofer ARC", transport_company_id: company.id,
        payment_mode: "daily_hg" } }
    end
    assert_equal company, Driver.order(:id).last.transport_company
    assert_difference("Driver.count", 1) do
      post drivers_url, params: { driver: { name: "Freelance", phone: "",
        transport_company_id: "", payment_mode: "round_trip" } }
    end
    assert_nil Driver.order(:id).last.transport_company
    assert_equal "round_trip", Driver.order(:id).last.payment_mode
  end

  test "operator can manage transport companies and reach related pages" do
    operator = User.create!(name: "Transport operator", email: "transport-operator@example.test",
      password: "password123", role: :operador)
    sign_out @admin
    sign_in operator

    get buses_url
    assert_response :success
    assert_select "a[href='#{transport_companies_path}']", text: "Empresas"
    assert_select "a[href='#{drivers_path}']", text: "Choferes"
    get transport_companies_url
    assert_response :success
    get transport_rates_url
    assert_response :success

    assert_difference("TransportCompany.count", 1) do
      post transport_companies_url, params: { transport_company: { name: "Empresa operadora" } }
    end
    company = TransportCompany.find_by!(name: "Empresa operadora")
    patch transport_company_url(company), params: { transport_company: {
      name: "Empresa operadora actualizada", vehicle_categories: %w[bus_large]
    } }
    assert_redirected_to transport_companies_url
    assert_equal "Empresa operadora actualizada", company.reload.name
    assert_equal ["bus_large"], company.vehicle_categories
  end

  test "accounting cannot manage transport companies" do
    accounting = User.create!(name: "Transport accounting", email: "transport-accounting@example.test",
      password: "password123", role: :contabilidad)
    sign_out @admin
    sign_in accounting

    get transport_companies_url
    assert_redirected_to root_path
    assert_no_difference("TransportCompany.count") do
      post transport_companies_url, params: { transport_company: { name: "No autorizada" } }
    end
    assert_redirected_to root_path
  end
end
