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

  test "driver must have company and phone when created" do
    company = TransportCompany.create!(name: "ARC Test")
    get drivers_url
    assert_response :success
    assert_select "select[name='driver[transport_company_id]']"
    assert_no_difference("Driver.count") do
      post drivers_url, params: { driver: { name: "Sin teléfono", transport_company_id: company.id } }
    end
    assert_difference("Driver.count", 1) do
      post drivers_url, params: { driver: { name: "Chofer nuevo", phone: "8888-1234",
        transport_company_id: company.id } }
    end
    assert_equal company, Driver.order(:id).last.transport_company
  end
end
