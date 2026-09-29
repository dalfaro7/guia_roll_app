require "test_helper"

class WhatsappTestMessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(
      name: "WhatsApp Admin",
      email: "whatsapp-admin@example.com",
      password: "password123",
      role: :admin
    )
    @operator = User.create!(
      name: "WhatsApp Operator",
      email: "whatsapp-operator@example.com",
      password: "password123",
      role: :operador
    )
  end

  test "admin can open the isolated test form" do
    sign_in @admin

    get new_whatsapp_test_message_url

    assert_response :success
    assert_select "input[name='whatsapp_test_message[to]']"
    assert_select "input[value='hello_world']"
  end

  test "unauthenticated visitor is challenged for review credentials" do
    get new_whatsapp_test_message_url

    assert_response :unauthorized
    assert_equal 'Basic realm="ARC_MESSAGE Review"', response.headers["WWW-Authenticate"]
  end

  test "review credentials grant access only to the isolated form" do
    with_review_credentials do |credentials|
      get new_whatsapp_test_message_url,
          headers: { "HTTP_AUTHORIZATION" => credentials }

      assert_response :success
      assert_select "strong", text: /Acceso de revisión de Meta/
      assert_select "a", text: "Work Days", count: 0
      assert_select "input[name='whatsapp_test_message[to]']"
    end
  end

  test "operator cannot run the account check" do
    sign_in @operator

    post check_whatsapp_test_message_url

    assert_redirected_to root_url
  end

  test "operator cannot open the test form" do
    sign_in @operator

    get new_whatsapp_test_message_url

    assert_redirected_to root_url
  end

  private

  def with_review_credentials
    old_username = ENV["META_REVIEW_USERNAME"]
    old_password = ENV["META_REVIEW_PASSWORD"]
    ENV["META_REVIEW_USERNAME"] = "meta-reviewer"
    ENV["META_REVIEW_PASSWORD"] = "temporary-secret"

    credentials = ActionController::HttpAuthentication::Basic.encode_credentials(
      "meta-reviewer",
      "temporary-secret"
    )
    yield credentials
  ensure
    ENV["META_REVIEW_USERNAME"] = old_username
    ENV["META_REVIEW_PASSWORD"] = old_password
  end
end
