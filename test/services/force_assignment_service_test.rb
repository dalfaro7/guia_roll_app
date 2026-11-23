require "test_helper"

class ForceAssignmentServiceTest < ActiveSupport::TestCase
  setup do
    @class_iii = Skill.find_or_create_by!(name: "ClassIII")
  end

  test "activating a guide adds availability to an existing open day" do
    guide = Guide.create!(name: "Late Balsa guide", priority: 4, active: false,
      pay_category: "freelance_regular", skills: [@class_iii])
    day = WorkDay.create!(date: Date.current + 2.days, status: :generated)
    assert_nil day.guide_days.find_by(guide: guide)

    guide.update!(active: true)

    assert day.guide_days.find_by!(guide: guide).standby?
  end

  test "operator can select a specific available level four Balsa guide" do
    guide = Guide.create!(name: "Selected Balsa guide", priority: 4, active: false,
      pay_category: "freelance_regular", skills: [@class_iii])
    day = WorkDay.create!(date: Date.current + 3.days, status: :generated)
    guide.update!(active: true)
    day.guide_days.find_by!(guide: guide).destroy!

    service = ForceAssignmentService.new(day, "Balsa", [@class_iii.id], guide_id: guide.id)
    service.call

    assert_equal guide, service.guide
    assert day.guide_days.find_by!(guide: guide).worked?
    assert_equal "Balsa", service.guide_day.location
    assert_equal 1, day.location_slots.where(location: "Balsa").count
    assert_equal 1, day.guides_requested
    assert_empty day.roll_coverage_errors

    assert_raises(RuntimeError) { service.call }
    assert_equal 1, day.location_slots.where(location: "Balsa").count
  end

  test "specific Balsa selection rejects a guide without Class III" do
    guide = Guide.create!(name: "Unqualified guide", priority: 4, active: true,
      pay_category: "freelance_regular")
    day = WorkDay.create!(date: Date.current + 4.days, status: :generated)

    service = ForceAssignmentService.new(day, "Balsa", [], guide_id: guide.id)
    assert_raises(RuntimeError) { service.call }
    assert_equal 0, day.location_slots.count
  end
end
