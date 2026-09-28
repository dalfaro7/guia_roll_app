require "test_helper"

class OfficeEmployeeDaysControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Test Admin",
      email: "test@example.com",
      password: "password123",
      password_confirmation: "password123",
      role: :admin
    )

    sign_in @user
  end

  test "should get index" do
    get office_employee_days_url
    assert_response :success
  end
test "operator cannot access office module" do
  sign_out @user
  operator = User.create!(
    name: "Test Operator",
    email: "office-operator@example.com",
    password: "password123",
    password_confirmation: "password123",
    role: :operador
  )
  sign_in operator

  [
    office_employee_days_url,
    office_holidays_url,
    office_day_credits_url,
    office_overtimes_url,
    office_vacation_credits_url
  ].each do |url|
    get url
    assert_redirected_to root_path
  end
end

end