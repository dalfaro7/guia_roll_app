require "test_helper"

class WorkDaysWeatherReportsLinkTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      name: "Roll Viewer",
      email: "roll-viewer@example.com",
      password: "password123"
    )
    sign_in @user
  end

  test "published roll links to weather reports" do
    work_day = WorkDay.create!(
      date: Date.current + 1.day,
      status: :published
    )

    get work_day_url(work_day)

    assert_response :success
    assert_select "a[href='#{weather_reports_path}']", text: /Reportes del río Balsa/
  end

  test "draft roll does not show the weather reports link" do
    work_day = WorkDay.create!(date: Date.current + 1.day, status: :draft)

    get work_day_url(work_day)

    assert_response :success
    assert_select "a[href='#{weather_reports_path}']", count: 0
  end
end
