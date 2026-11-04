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
end
