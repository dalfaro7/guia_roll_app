require "test_helper"

class Whatsapp::ClientTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:code, :body)

  class FakeHttp
    attr_reader :request_value

    def initialize(response)
      @response = response
    end

    def request(request)
      @request_value = request
      @response
    end
  end

  test "sends a template without reading any application model" do
    http = FakeHttp.new(
      FakeResponse.new("200", { messages: [{ id: "wamid.123" }] }.to_json)
    )
    client = Whatsapp::Client.new(
      access_token: "secret-token",
      phone_number_id: "1376920292169514",
      api_version: "v25.0",
      http: http
    )

    result = client.send_template(
      to: "+506 8888-8888",
      template_name: "hello_world",
      language_code: "en_US"
    )

    assert result.success?
    assert_equal 200, result.status
    assert_equal "Bearer secret-token", http.request_value["Authorization"]

    payload = JSON.parse(http.request_value.body)
    assert_equal "50688888888", payload["to"]
    assert_equal "template", payload["type"]
    assert_equal "hello_world", payload.dig("template", "name")
    assert_equal "en_US", payload.dig("template", "language", "code")
  end

  test "reports a Meta error without raising" do
    http = FakeHttp.new(
      FakeResponse.new("400", { error: { message: "Invalid parameter" } }.to_json)
    )
    client = Whatsapp::Client.new(
      access_token: "secret-token",
      phone_number_id: "123",
      http: http
    )

    result = client.send_template(
      to: "50688888888",
      template_name: "hello_world",
      language_code: "en_US"
    )

    assert_not result.success?
    assert_equal 400, result.status
    assert_equal "Invalid parameter", result.body.dig("error", "message")
  end

test "reads phone numbers for the configured business account" do
  http = FakeHttp.new(
    FakeResponse.new("200", { data: [{ id: "1376920292169514" }] }.to_json)
  )
  client = Whatsapp::Client.new(
    access_token: "secret-token",
    business_account_id: "1092016140140500",
    http: http
  )

  result = client.phone_numbers

  assert result.success?
  assert_equal "Bearer secret-token", http.request_value["Authorization"]
  assert_equal "1376920292169514", result.body.dig("data", 0, "id")
end

  test "requires server configuration" do
    client = Whatsapp::Client.new(access_token: nil, phone_number_id: nil)

    error = assert_raises(Whatsapp::Client::ConfigurationError) do
      client.send_template(
        to: "50688888888",
        template_name: "hello_world",
        language_code: "en_US"
      )
    end

    assert_includes error.message, "WHATSAPP_ACCESS_TOKEN"
    assert_includes error.message, "WHATSAPP_PHONE_NUMBER_ID"
  end
end
