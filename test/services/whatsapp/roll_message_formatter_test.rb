require "test_helper"

class Whatsapp::RollMessageFormatterTest < ActiveSupport::TestCase
  test "formats the published roll by location and operational status" do
    river_guide = Guide.create!(name: "Guide One", priority: 1, active: true)
    safety_guide = Guide.create!(name: "Guide Two", priority: 1, active: true)
    task_guide = Guide.create!(name: "Guía de Tarea", priority: 2, active: true)
    waiting_guide = Guide.create!(name: "Guía en Espera", priority: 3, active: true)
    work_day = WorkDay.create!(date: Date.new(2026, 10, 7), status: :published)

    work_day.guide_days.find_by!(guide: river_guide).update!(
      status: :worked, location: "Balsa", role_primary: "River Guide", role_secondary: nil
    )
    work_day.guide_days.find_by!(guide: safety_guide).update!(
      status: :worked, location: "Balsa", role_primary: "Safety Kayaker", role_secondary: nil
    )
    work_day.guide_days.find_by!(guide: task_guide).update!(
      status: :assigned_task, status_note: "Revisar equipo"
    )

    message = Whatsapp::RollMessageFormatter.new(work_day).call

    assert_includes message, "📅 *Wednesday, October 7, 2026*"
    assert_includes message, "🛶 *BALSA*"
    assert_includes message, "1. Guide One — River Guide"
    assert_includes message, "🛟 Guide Two — Safety Kayaker"
    assert_includes message, "📌 *ASSIGNED TASKS*"
    assert_includes message, "• Guía de Tarea — Revisar equipo"
    assert_includes message, "⏳ *STANDBY*"
    assert_includes message, "• Guía en Espera"
  end
end
