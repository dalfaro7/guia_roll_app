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
end