require "test_helper"

class WeatherReportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      name: "Report Viewer",
      email: "report-viewer@example.com",
      password: "password123"
    )
  end

  test "requires a signed in user" do
    get weather_reports_url

    assert_redirected_to new_user_session_url
  end

  test "shows only the two newest reports" do
    sign_in @user
    create_report("old", 3.hours.ago)
    second = create_report("second", 2.hours.ago)
    newest = create_report("newest", 1.hour.ago)

    get weather_reports_url

    assert_response :success
    assert_select "article.weather-report-card", count: 2
    assert_includes response.body, newest.title
    assert_includes response.body, second.title
    assert_not_includes response.body, "Informe old"
  end

  private

  def create_report(uid, reported_at)
    WeatherReport.create!(
      source_uid: uid,
      title: "Informe #{uid}",
      body: "Contenido #{uid}",
      reported_at: reported_at,
      source_name: "ChatGPT",
      source_url: "https://chatgpt.com/share/example"
    )
  end
end
