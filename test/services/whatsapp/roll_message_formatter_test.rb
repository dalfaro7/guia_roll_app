require "test_helper"

class Whatsapp::RollMessageFormatterTest < ActiveSupport::TestCase
  test "formats a variable number of guides in one line" do
    river_guide = Guide.create!(name: "Guide One", priority: 1, active: true)
    safety_guide = Guide.create!(name: "Guide Two", priority: 1, active: true)
    extra_guide = Guide.create!(name: "Guide Three", priority: 1, active: true)
    task_guide = Guide.create!(name: "Task Guide", priority: 2, active: true)
    waiting_guide = Guide.create!(name: "Waiting Guide", priority: 3, active: true)
    work_day = WorkDay.create!(date: Date.new(2026, 10, 7), status: :published)

    work_day.guide_days.find_by!(guide: river_guide).update!(
      status: :worked, location: "Balsa", role_primary: "River Guide", role_secondary: nil
    )
    work_day.guide_days.find_by!(guide: safety_guide).update!(
      status: :worked, location: "Balsa", role_primary: "Safety Kayaker", role_secondary: nil
    )
    work_day.guide_days.find_by!(guide: extra_guide).update!(
      status: :worked, location: "Balsa", role_primary: "River Guide", role_secondary: nil
    )
    work_day.guide_days.find_by!(guide: task_guide).update!(
      status: :assigned_task, status_note: "Inspect\nequipment"
    )

    message = Whatsapp::RollMessageFormatter.new(work_day).template_parameter

    assert_includes message, "📅 Wednesday, October 7, 2026"
    assert_includes message, "🛶 BALSA:"
    assert_includes message, "1. Guide One — River Guide"
    assert_includes message, "2. Guide Three — River Guide"
    assert_includes message, "🛟 Guide Two — Safety Kayaker"
    assert_includes message, "📌 ASSIGNED TASKS: Task Guide — Inspect equipment"
    assert_includes message, "⏳ STANDBY: Waiting Guide"
    assert_no_match(/[\r\n\t]/, message)
  end
end
