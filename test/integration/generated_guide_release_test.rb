require "test_helper"

class GeneratedGuideReleaseTest < ActionDispatch::IntegrationTest
  setup do
    @operator = User.create!(name: "Release operator", email: "release-operator@example.test",
      password: "password123", role: :operador)
    @guide = Guide.create!(name: "Released guide", priority: 3, active: true,
      day_off_balance: 2, pay_category: "freelance_regular")
    @other = Guide.create!(name: "Remaining guide", priority: 3, active: true,
      pay_category: "freelance_regular")
    @day = WorkDay.create!(date: Date.current + 5.days, status: :generated)
    2.times { @day.location_slots.create!(location: "Balsa") }
    @guide_day = @day.guide_days.find_by!(guide: @guide)
    @other_day = @day.guide_days.find_by!(guide: @other)
    [@guide_day, @other_day].each do |day|
      day.update!(status: :worked, location: "Balsa", role_primary: "River Guide")
    end
    departure = @day.departures.find_or_create_by!(label: "Balsa") do |record|
      record.location = "Balsa"
      record.starts_at = Departure.fixed_start_for(@day.date, "Balsa")
    end
    @assignment = CompensationAssignment.find_or_create_by!(guide_day: @guide_day) do |record|
      record.departure = departure
      record.guide = @guide
      record.role_code = "river_guide"
      record.status = "planned"
      record.source = "manual"
    end
    @assignment.compensation_lines.create!(code: "guide_regular", rate_cents: 5_000,
      amount_cents: 5_000, applied_at: Time.current)
    sign_in @operator
  end

  test "release changes only the selected guide and removes active compensation" do
    get confirm_release_guide_work_day_path(@day, guide_day_id: @guide_day.id)
    assert_response :success
    assert_select "h1", text: /Released guide/

    post release_guide_work_day_path(@day), params: { guide_day_id: @guide_day.id }

    assert_redirected_to work_day_path(@day)
    assert @guide_day.reload.day_off?
    assert_nil @guide_day.location
    assert_nil @guide_day.role_primary
    assert_equal 1, @guide.reload.day_off_balance
    assert @other_day.reload.worked?
    assert_equal 2, @day.location_slots.count
    assert_includes @day.roll_coverage_errors, "Balsa: falta 1 puesto por cubrir"
    assert_equal "canceled", @assignment.reload.status
    assert @assignment.canceled_by_schedule?
    assert_equal 0, @assignment.total_cents
    assert_equal 0, CompensationAssignment.active.where(guide: @guide).count

    get work_day_compensation_path(@day)
    assert_response :success
    assert_select "td", text: "Released guide", count: 0
  end

  test "published programming cannot release an assigned guide" do
    @day.update!(status: :published)
    post release_guide_work_day_path(@day), params: { guide_day_id: @guide_day.id }

    assert_redirected_to work_day_path(@day)
    assert @guide_day.reload.worked?
    assert_equal "planned", @assignment.reload.status
  end

  test "an already released guide cannot consume another free day" do
    post release_guide_work_day_path(@day), params: { guide_day_id: @guide_day.id }
    post release_guide_work_day_path(@day), params: { guide_day_id: @guide_day.id }

    assert_equal 1, @guide.reload.day_off_balance
    assert @guide_day.reload.day_off?
  end
end
