require "test_helper"

class GuideOutsideRollDaysTest < ActiveSupport::TestCase
  test "counts inactive dates and vacation once, excludes reactivation and future" do
    travel_to Time.zone.local(2026, 11, 1, 12) do
      guide = Guide.create!(name: "Activity History", priority: 990, active: true)
      vacation = WorkDay.create!(date: Date.new(2026, 11, 3))
      vacation.guide_days.find_by!(guide: guide).update!(status: :vacation)
      future = WorkDay.create!(date: Date.new(2026, 11, 20))
      future.guide_days.find_by!(guide: guide).update!(status: :vacation)
      travel 2.days
      guide.update!(active: false)
      travel 2.days
      guide.update!(active: true)
      result = GuideOutsideRollDays.call(guides: [guide], month: Date.current).fetch(guide.id)
      assert_equal 2, result[:count]
      assert result[:complete]
      assert_equal [true, false, true], guide.guide_activity_changes.order(:recorded_at).pluck(:active)
    end
  end

  test "missing old history is partial rather than invented inactive days" do
    guide = Guide.create!(name: "Legacy Activity", priority: 991, active: false)
    guide.update_column(:created_at, 2.months.ago)
    result = GuideOutsideRollDays.call(guides: [guide], month: Date.current.prev_month).fetch(guide.id)
    assert_equal 0, result[:count]
    assert_not result[:complete]
  end
end
