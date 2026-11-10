require "test_helper"

class SaraRollFlowTest < ActiveSupport::TestCase
  test "generated Sara guide fills PM as second outing and publishes with two opportunities" do
    class_iv = Skill.find_or_create_by!(name: "ClassIV")
    sara_roll = Skill.find_or_create_by!(name: "Roll de Sara")
    guide = Guide.create!(name: "Full Sara PM flow", priority: 5, active: true,
      pay_category: "freelance_regular", skills: [class_iv, sara_roll])
    actor = User.create!(name: "Full flow operator",
      email: "full-flow-operator@example.test", password: "password123",
      role: :operador)
    CompensationRate.find_or_create_by!(code: "guide_regular",
      effective_at: Time.utc(2020, 1, 1)) do |rate|
      rate.amount_cents = 5_000
    end
    CompensationDiscountRule.find_or_create_by!(code: "second_sara",
      effective_at: Time.utc(2020, 1, 1)) do |rule|
      rule.percent = 20
    end
    day = WorkDay.create!(date: Date.current + 55.days)
    sara_slot = day.location_slots.create!(location: "Sara-3&4")
    sara_slot.skills << class_iv
    pm_slot = day.location_slots.create!(location: "PM")
    pm_slot.skills << class_iv

    day.generate_roles!

    assert day.reload.generated?
    assert_equal "Sara-3&4", day.guide_days.find_by!(guide: guide).location
    assert_equal ["PM: falta 1 puesto por cubrir"], day.roll_coverage_errors
    assert_raises(ActiveRecord::RecordInvalid) { day.publish! }

    SaraManualAssignment.new(day).call(slot_id: pm_slot.id,
      guide_id: guide.id, actor: actor)

    assert_empty day.roll_coverage_errors
    assert_equal 2, day.assigned_roll_count
    assert_equal 2, RollFairnessPolicy.roll_worked_days_for_guide(guide,
      before_date: day.date + 1.day)
    assignments = CompensationAssignment.joins(:departure)
      .where(guide: guide, departures: { work_day_id: day.id })
      .includes(:departure)
      .sort_by { |assignment| assignment.departure.starts_at }
    assert_equal %w[Sara-3&4 PM], assignments.map { |assignment| assignment.departure.location }
    assert_equal 20, assignments.last.compensation_lines
      .find_by!(code: "guide_regular").discount_percent

    day.publish!

    assert day.reload.published?
    sections = Whatsapp::RollDocumentFormatter.new(day).sections
    assert_equal [guide.name], sections.find { |section| section[:title] == "SARA 3 & 4" }[:rows].pluck(:name)
    assert_equal [guide.name], sections.find { |section| section[:title] == "PM" }[:rows].pluck(:name)
  end
end
