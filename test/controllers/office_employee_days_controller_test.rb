require "test_helper"

class OfficeEmployeeDaysControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = User.create!(
      name: "Test Admin",
      email: "admin@example.com",
      password: "password123",
      password_confirmation: "password123",
      role: :admin
    )
  end

  test "administrator can access office module" do
    sign_in @admin
    office_index_urls.each do |url|
      get url
      assert_response :success
    end
  end

  test "human resources has read only access to office module" do
    human_resources = User.create!(
      name: "Human Resources",
      email: "hr@example.com",
      password: "password123",
      password_confirmation: "password123",
      role: :recursos_humanos
    )
    sign_in human_resources

    office_index_urls.each do |url|
      get url
      assert_response :success
    end

    [
      new_office_employee_day_url,
      new_office_holiday_url,
      new_office_day_credit_url,
      new_office_overtime_url,
      new_office_vacation_credit_url
    ].each do |url|
      get url
      assert_redirected_to root_path
    end

    post generate_month_office_employee_days_url,
         params: { month: Date.current.strftime("%Y-%m") }
    assert_redirected_to root_path
  end

  test "operator cannot access office module" do
    operator = User.create!(
      name: "Test Operator",
      email: "office-operator@example.com",
      password: "password123",
      password_confirmation: "password123",
      role: :operador
    )
    sign_in operator

    office_index_urls.each do |url|
      get url
      assert_redirected_to root_path
    end
  end

  private

  def office_index_urls
    [
      office_employee_days_url,
      office_holidays_url,
      office_day_credits_url,
      office_overtimes_url,
      office_vacation_credits_url
    ]
  end
end
