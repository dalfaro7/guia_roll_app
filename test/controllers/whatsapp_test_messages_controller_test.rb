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
end
