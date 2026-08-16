require "test_helper"

class AuditLogsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      name: "Test Admin",
      email: "audit_test@example.com",
      password: "password123",
      password_confirmation: "password123",
      role: :admin
    )

    sign_in @user
  end

  test "should get index" do
    get audit_logs_url
    assert_response :success
  end
end
