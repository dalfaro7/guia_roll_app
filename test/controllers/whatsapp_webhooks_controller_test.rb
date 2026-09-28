require "test_helper"
require "openssl"

class WhatsappWebhooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @old_verify_token = ENV["WHATSAPP_WEBHOOK_VERIFY_TOKEN"]
    @old_app_secret = ENV["META_APP_SECRET"]
    ENV["WHATSAPP_WEBHOOK_VERIFY_TOKEN"] = "test-verify-token"
    ENV["META_APP_SECRET"] = "test-app-secret"
  end

  teardown do
    ENV["WHATSAPP_WEBHOOK_VERIFY_TOKEN"] = @old_verify_token
    ENV["META_APP_SECRET"] = @old_app_secret
  end

  test "verifies a valid Meta subscription challenge" do
    get "/webhooks/whatsapp", params: {
      "hub.mode" => "subscribe",
      "hub.verify_token" => "test-verify-token",
      "hub.challenge" => "challenge-123"
    }

    assert_response :success
    assert_equal "challenge-123", response.body
  end

  test "rejects an invalid verification token" do
    get "/webhooks/whatsapp", params: {
      "hub.mode" => "subscribe",
      "hub.verify_token" => "wrong-token",
      "hub.challenge" => "challenge-123"
    }

    assert_response :forbidden
  end

  test "accepts a webhook with a valid Meta signature" do
    payload = { object: "whatsapp_business_account", entry: [] }.to_json
    signature = OpenSSL::HMAC.hexdigest(
      "SHA256",
      ENV.fetch("META_APP_SECRET"),
      payload
    )

    post "/webhooks/whatsapp",
         params: payload,
         headers: {
           "CONTENT_TYPE" => "application/json",
           "X-Hub-Signature-256" => "sha256=#{signature}"
         }

    assert_response :success
  end

  test "rejects a webhook with an invalid signature" do
    post "/webhooks/whatsapp",
         params: { object: "whatsapp_business_account" }.to_json,
         headers: {
           "CONTENT_TYPE" => "application/json",
           "X-Hub-Signature-256" => "sha256=invalid"
         }

    assert_response :unauthorized
  end
end
