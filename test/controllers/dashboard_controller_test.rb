require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      email: "dashboard_test@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "Test User"
    )

    sign_in @user
  end

  test "should get index" do
    get dashboard_url
    assert_response :success
  end
end