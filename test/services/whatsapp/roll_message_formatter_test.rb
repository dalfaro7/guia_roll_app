require "test_helper"

class Whatsapp::RollMessageFormatterTest < ActiveSupport::TestCase
  test "formats seven single-line template parameters" do
    river_guide = Guide.create!(name: "Guide One", priority: 1, active: true)
    safety_guide = Guide.create!(name: "Guide Two", priority: 1, active: true)
    task_guide = Guide.create!(name: "Task Guide", priority: 2, active: true)
    waiting_guide = Guide.create!(name: "Waiting Guide", priority: 3, active: true)
    work_day = WorkDay.create!(date: Date.new(2026, 10, 7), status: :published)

    work_day.guide_days.find_by!(guide: river_guide).update!(
      status: :worked, location: "Balsa", role_primary: "River Guide", role_secondary: nil
    )
    work_day.guide_days.find_by!(guide: safety_guide).update!(
      status: :worked, location: "Balsa", role_primary: "Safety Kayaker", role_secondary: nil
    )
    work_day.guide_days.find_by!(guide: task_guide).update!(
      status: :assigned_task, status_note: "Inspect\nequipment"
    )

    parameters = Whatsapp::RollMessageFormatter.new(work_day).template_parameters

    assert_equal 7, parameters.length
    assert_equal "Wednesday, October 7, 2026", parameters[0]
    assert_equal "None", parameters[1]
    assert_includes parameters[2], "1. Guide One — River Guide"
    assert_includes parameters[2], "🛟 Guide Two — Safety Kayaker"
    assert_equal "None", parameters[3]
    assert_equal "None", parameters[4]
    assert_equal "Task Guide — Inspect equipment", parameters[5]
    assert_includes parameters[6], "Waiting Guide"
    parameters.each { |parameter| assert_no_match(/[\r\n\t]/, parameter) }
  end
end
