require "test_helper"

class OfficeDayCreditsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      name: "Test User",
      email: "test@example.com",
      password: "password123",
      password_confirmation: "password123"
    )

    sign_in @user
  end

  test "should get index" do
    get office_day_credits_url
    assert_response :success
  end
end