require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      email: "dashboard_test@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "Test User"
    )

    sign_in @user
  end

  test "should get index" do
    get dashboard_url
    assert_response :success
  end
  test "equity detail counts recorded monthly days and preserves assignments" do
    guide = Guide.create!(name: "Equity Counter Guide", priority: 900, active: true)
    empty_guide = Guide.create!(name: "Equity Empty Guide", priority: 901, active: true)
    month = Date.current.next_month.beginning_of_month
    %w[day_off day_off penalized worked worked assigned_task standby vacation].each_with_index do |status, index|
      day = WorkDay.create!(date: month + index)
      record = day.guide_days.find_by!(guide: guide)
      record.update!(status: status, status_note: "Dashboard test")
    end
    other_day = WorkDay.create!(date: month.next_month)
    other_day.guide_days.find_by!(guide: guide).update!(status: :penalized, status_note: "Other month")

    get dashboard_url(month: month.strftime("%Y-%m"))
    assert_response :success
    assert_select 'tr[data-equity-guide="Equity Counter Guide"]' do
      assert_select "td:nth-child(2)", text: "2"
      assert_select "td:nth-child(3)", text: "1"
      assert_select "td:nth-child(5) strong", text: "1"
      assert_select "td:nth-child(6) strong", text: "2"
    end
    assert_select 'tr[data-equity-guide="Equity Empty Guide"]' do
      assert_select "td:nth-child(2)", text: "0"
      assert_select "td:nth-child(3)", text: "0"
      assert_select "td:nth-child(5) strong", text: "0"
      assert_select "td:nth-child(6) strong", text: "0"
    end
  end

  test "annual incident total includes grouped PostgreSQL month values" do
    day = WorkDay.create!(date: Date.current + 1.day)
    RollNote.create!(work_day: day, created_by: @user, note_type: :incident, note: "Test incident")
    get dashboard_url(incident_year: day.date.year)
    assert_response :success
    assert_select ".equity-incident-summary span:last-child strong", text: "1"
  end

end