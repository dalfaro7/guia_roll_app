require "test_helper"

class OfficeDayCreditsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      name: "Test User",
      email: "test@example.com",
      password: "password123",
      password_confirmation: "password123",
      role: :admin
    )

    sign_in @user
  end

  test "should get index" do
    get office_day_credits_url
    assert_response :success
  end
test "operator cannot access office day credits" do
  sign_out @user
  operator = User.create!(
    name: "Test Operator",
    email: "operator@example.com",
    password: "password123",
    password_confirmation: "password123",
    role: :operador
  )
  sign_in operator

  get office_day_credits_url

  assert_redirected_to root_path
end

end