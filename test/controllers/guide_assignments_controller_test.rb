require "test_helper"

class GuideAssignmentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    user = User.create!(
      email: "guide_lookup_test@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "Guide Lookup Test"
    )
    sign_in user
    @guide = Guide.create!(
      name: "Guide for Lookup",
      priority: 2,
      active: true
    )
  end

  test "date range includes both boundaries and excludes later assignments" do
    first_date = Date.current + 1.day
    last_date = Date.current + 2.days
    outside_date = Date.current + 3.days

    [first_date, last_date, outside_date].each do |date|
      WorkDay.create!(date: date, status: :draft, guides_requested: 0)
    end

    get guide_assignments_path, params: {
      range_guide_id: @guide.id,
      start_date: first_date.iso8601,
      end_date: last_date.iso8601
    }

    assert_response :success
    assert_select "table tbody tr", count: 2
    assert_select "table tbody td:first-child", text: first_date.to_s
    assert_select "table tbody td:first-child", text: last_date.to_s
    assert_select "table tbody td:first-child", text: outside_date.to_s, count: 0
  end

  test "reversed date range shows a validation message" do
    get guide_assignments_path, params: {
      range_guide_id: @guide.id,
      start_date: (Date.current + 2.days).iso8601,
      end_date: (Date.current + 1.day).iso8601
    }

    assert_response :success
    assert_select ".alert", text: "End date must be on or after start date."
  end
end
