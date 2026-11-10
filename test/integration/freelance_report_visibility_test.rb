require "test_helper"

class FreelanceReportVisibilityTest < ActionDispatch::IntegrationTest
  setup do
    sign_in User.create!(name: "Reports admin", email: "report-scope@example.test",
      password: "password123", role: :admin)
    @regular = Guide.create!(name: "Regular report guide", priority: 5, active: true)
    @freelance = Guide.create!(name: "Freelance hidden guide", priority: 6, active: true)
    @day = WorkDay.create!(date: Date.tomorrow)
  end

  test "free day report excludes freelance rows and selection without deleting their records" do
    record = @day.guide_days.find_by!(guide: @freelance)
    record.update!(status: :day_off)
    get day_off_report_path(month: @day.date.strftime("%Y-%m"))
    assert_response :success
    assert_select "body", text: /Regular report guide/
    assert_select "body", text: /Freelance hidden guide/, count: 0
    assert record.reload.day_off?
  end

  test "equity totals charts and filters exclude freelance work while preserving it" do
    regular = @day.guide_days.find_by!(guide: @regular)
    regular.update!(status: :worked, role_primary: "Safety Kayaker", location: "Sara-3&4")
    freelance = @day.guide_days.find_by!(guide: @freelance)
    freelance.update!(status: :worked, role_primary: "Safety Kayaker", location: "Sara-3&4")
    get dashboard_path(month: @day.date.strftime("%Y-%m"))
    assert_response :success
    assert_select 'tr[data-equity-guide="Regular report guide"]'
    assert_select 'tr[data-equity-guide="Freelance hidden guide"]', count: 0
    assert_select "#equity-roles", text: /Freelance hidden guide/, count: 0
    assert_select 'tr[data-equity-guide="Regular report guide"] td:nth-child(4)', text: "100.0%"
    assert freelance.reload.worked?
  end

  test "programming hides freelance only in equity and keeps them in operational availability" do
    get work_day_path(@day)
    assert_response :success
    assert_select "#day-fairness", text: /Freelance hidden guide/, count: 0
    assert_select "#day-fairness", text: /Regular report guide/
    assert_select "body", text: /Freelance hidden guide/
    assert @day.guide_days.exists?(guide: @freelance)
  end
end
