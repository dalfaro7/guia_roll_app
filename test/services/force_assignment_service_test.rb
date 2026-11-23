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

  test "force assignment uses the fair candidate and rejects a selected guide" do
    skill = Skill.create!(name: "Fairness service test")
    day = WorkDay.create!(date: Date.current + 3.days, status: :generated)
    guides = ["First", "Second"].map do |name|
      Guide.create!(name: "#{name} fairness guide", priority: 4, active: true,
        pay_category: "freelance_regular", skills: [skill])
    end
    expected = GuideCandidateRanker.new(work_day: day,
      skill_ids: [skill.id]).next_candidate.guide
    other = (guides - [expected]).first

    assert_raises(ArgumentError) do
      ForceAssignmentService.new(day, "Balsa", [skill.id], guide_id: other.id)
    end

    service = ForceAssignmentService.new(day, "Balsa", [skill.id])
    service.call

    assert_equal expected, service.guide
    assert day.guide_days.find_by!(guide: expected).worked?
    assert day.guide_days.find_by!(guide: other).standby?
    assert_equal 1, day.location_slots.where(location: "Balsa").count
    assert_empty day.roll_coverage_errors
  end
end
