require "test_helper"

class WeatherReportImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_token = ENV["WEATHER_REPORT_SYNC_TOKEN"]
    ENV["WEATHER_REPORT_SYNC_TOKEN"] = "weather-secret"
  end

  teardown do
    ENV["WEATHER_REPORT_SYNC_TOKEN"] = @original_token
  end

  test "rejects imports without the sync token" do
    post weather_report_import_url, params: { reports: [report_payload] }, as: :json

    assert_response :unauthorized
    assert_equal 0, WeatherReport.count
  end

  test "imports reports and updates an existing source uid" do
    post weather_report_import_url,
         params: { reports: [report_payload] },
         headers: authorization_header,
         as: :json

    assert_response :success
    assert_equal 1, WeatherReport.count
    assert_equal "Primer contenido", WeatherReport.first.body

    updated_payload = report_payload.merge(body: "Contenido actualizado")
    post weather_report_import_url,
         params: { reports: [updated_payload] },
         headers: authorization_header,
         as: :json

    assert_response :success
    assert_equal 1, WeatherReport.count
    assert_equal "Contenido actualizado", WeatherReport.first.reload.body
  end

  private

  def authorization_header
    { "Authorization" => "Bearer weather-secret" }
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
