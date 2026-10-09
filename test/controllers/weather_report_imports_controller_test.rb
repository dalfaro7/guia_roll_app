require "test_helper"
require "base64"
require "openssl"
require "tempfile"

class WeatherReportImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_public_key_path = ENV["WEATHER_REPORT_SYNC_PUBLIC_KEY_PATH"]
    @private_key = OpenSSL::PKey::RSA.new(2048)
    @public_key_file = Tempfile.new("weather-report-public-key")
    @public_key_file.write(@private_key.public_key.to_pem)
    @public_key_file.flush
    ENV["WEATHER_REPORT_SYNC_PUBLIC_KEY_PATH"] = @public_key_file.path
  end

  teardown do
    ENV["WEATHER_REPORT_SYNC_PUBLIC_KEY_PATH"] = @original_public_key_path
    @public_key_file.close!
  end

  test "rejects imports without a signature" do
    post weather_report_import_url,
         params: JSON.generate(reports: [report_payload]),
         headers: { "Content-Type" => "application/json" }

    assert_response :unauthorized
    assert_equal 0, WeatherReport.count
  end

  test "rejects an expired signature" do
    payload = JSON.generate(reports: [report_payload])

    post weather_report_import_url,
         params: payload,
         headers: signed_headers(payload, 10.minutes.ago.to_i)

    assert_response :unauthorized
    assert_equal 0, WeatherReport.count
  end

  test "imports reports and updates an existing source uid" do
    payload = JSON.generate(reports: [report_payload])
    post weather_report_import_url,
         params: payload,
         headers: signed_headers(payload)

    assert_response :success
    assert_equal 1, WeatherReport.count
    assert_equal "Primer contenido", WeatherReport.first.body

    updated_payload = JSON.generate(
      reports: [report_payload.merge(body: "Contenido actualizado")]
    )
    post weather_report_import_url,
         params: updated_payload,
         headers: signed_headers(updated_payload)

    assert_response :success
    assert_equal 1, WeatherReport.count
    assert_equal "Contenido actualizado", WeatherReport.first.reload.body
  end

  private

  def signed_headers(payload, timestamp = Time.current.to_i)
    signature = @private_key.sign(
      OpenSSL::Digest::SHA256.new,
      "#{timestamp}.#{payload}"
    )

    {
      "Content-Type" => "application/json",
      "X-Weather-Report-Timestamp" => timestamp.to_s,
      "X-Weather-Report-Signature" => Base64.strict_encode64(signature)
    }
  end

  def report_payload
    {
      source_uid: "chatgpt-report-123",
      title: "Informe meteorológico operativo",
      body: "Primer contenido",
      reported_at: Time.current.iso8601,
      source_name: "ChatGPT - Clima Balsa mañana y noche",
      source_url: "https://chatgpt.com/share/6ac9730e-a600-83e8-a6bd-b0e7401705d9"
    }
  end
end
