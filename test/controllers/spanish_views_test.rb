require "test_helper"

class SpanishViewsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in User.create!(name: "Spanish Test", email: "spanish@example.test", password: "test-password", role: :admin)
  end

  test "work day labels are translated without changing submitted role values" do
    guide = Guide.create!(name: "Spanish Guide", priority: 2, active: true)
    day = WorkDay.create!(date: Date.current + 1.day, status: :generated)
    day.guide_days.find_by!(guide: guide).update!(status: :worked, role_primary: "River Guide")
    get work_day_path(day)
    assert_response :success
    assert_select 'option[value="River Guide"]', text: "Guía de río"
    assert_select 'option[value="Safety Kayaker"]', text: "Kayakista de seguridad"
    assert_select 'html[lang="es"]'
  end

  test "main views render in Spanish" do
    [guides_path, new_guide_path, buses_path, new_bus_path, dashboard_path, guide_assignments_path, day_off_report_path, audit_logs_path].each do |path|
      get path
      assert_response :success
      assert_select 'html[lang="es"]'
      assert_not_includes response.body, "Translation missing"
    end
    get new_bus_path
    assert_select 'label', text: "Capacidad"
    get dashboard_path
    assert_select 'h1', text: "Panel de equidad"
    assert_select 'th', text: "Diferencia vs. promedio"
  end
end
