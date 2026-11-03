require "test_helper"

class GuideAssignmentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @zone = Time.find_zone!("America/Costa_Rica")
    @admin = User.create!(name: "Report admin", email: "weekly-report-admin@example.test",
      password: "password123", role: :admin)
    sign_in @admin
    @guide = Guide.create!(name: "A Guide", priority: 2, active: true,
      pay_category: "freelance_regular")
  end

  test "opens the last closed Wednesday to Tuesday week and first guide" do
    Guide.create!(name: "Z Guide", priority: 3, active: true)
    travel_to @zone.local(2026, 11, 11, 12) do
      get guide_assignments_path
      assert_response :success
      assert_select "h1", "Reportes semanales"
      assert_select "h2", @guide.name
      assert_select "table tbody tr", count: 7
      assert_select "p", text: /04\/11\/2026.*10\/11\/2026/
      assert_select "[data-bs-toggle='modal']", count: 7
    end
  end

  test "Tuesday becomes the latest closed week at 20:00 Costa Rica" do
    travel_to @zone.local(2026, 11, 10, 19, 59) do
      get guide_assignments_path
      assert_select "p", text: /28\/10\/2026.*03\/11\/2026/
    end
    travel_to @zone.local(2026, 11, 10, 20) do
      get guide_assignments_path
      assert_select "p", text: /04\/11\/2026.*10\/11\/2026/
    end
  end

  test "past week shows Host as text and performed output with detailed pay" do
    week_start = Date.current + ((3 - Date.current.wday) % 7) + 7.days
    until (week_start + 2.days).month == (week_start + 6.days).month &&
        ((week_start + 2.days).day <= 15) == ((week_start + 6.days).day <= 15)
      week_start += 7.days
    end
    host_date = week_start + 1.day
    paid_date = week_start + 2.days
    report_date = week_start + 7.days
    CompensationRate.create!(code: "guide_regular", amount_cents: 5_000,
      effective_at: Time.utc(2020, 1, 1))
    CompensationRate.create!(code: "bonus_photo_take_and_send", amount_cents: 2_000,
      effective_at: Time.utc(2020, 1, 1))
    CompensationDiscountRule.create!(code: "second_sara", percent: 20,
      effective_at: Time.utc(2020, 1, 1))

    host_day = WorkDay.create!(date: host_date, guides_requested: 0)
    host_day.guide_days.create!(guide: @guide, status: :assigned_task,
      status_note: "Host")
    paid_day = WorkDay.create!(date: paid_date, guides_requested: 0)
    departure = paid_day.departures.create!(label: "Balsa mañana", location: "Balsa",
      starts_at: @zone.local(paid_date.year, paid_date.month, paid_date.day, 6),
      status: "completed")
    assignment = departure.compensation_assignments.create!(guide: @guide,
      role_code: "river_guide", photo_task: "take_and_send", status: "performed")
    second_departure = paid_day.departures.create!(label: "Sara tarde", location: "Sara-3",
      starts_at: @zone.local(paid_date.year, paid_date.month, paid_date.day, 10),
      status: "completed")
    second_assignment = second_departure.compensation_assignments.create!(guide: @guide,
      role_code: "river_guide", status: "performed")
    Compensation::RepriceDay.call(paid_day)

    travel_to @zone.local(report_date.year, report_date.month, report_date.day, 12) do
      CompensationCloseDueDaysJob.perform_now
      get guide_assignments_path, params: { guide_id: @guide.id, week: paid_date.iso8601 }
      assert_response :success
      assert_select "table tbody tr", count: 7
      assert_select "td", text: /Host/
      assert_select "td", text: /Balsa mañana.*Toma y envía fotos/
      modal_id = "#weekly-day-#{paid_date.strftime("%Y%m%d")}"
      assert_select modal_id, count: 1
      assert_select "button[data-bs-target='#{modal_id}']", count: 1
      assert_select modal_id, text: /Guía regular/
      assert_select modal_id, text: /Toma y envía fotos/
      assert_select modal_id, text: /Sara tarde/
      assert_select modal_id, text: /descuento 20%/
      assert_select "tfoot", text: /110[,.]00/
      assert_select "[aria-label*='Ganancias de la quincena'][aria-label*='110']", count: 1
      assert_select "[aria-label*='Ganancias del mes'][aria-label*='110']", count: 1
      assert_equal 7_000, assignment.reload.total_cents
      assert_equal 4_000, second_assignment.reload.total_cents
    end
  end

  test "an open or future week cannot be queried" do
    travel_to @zone.local(2026, 11, 11, 12) do
      get guide_assignments_path, params: { week: "2026-11-11" }
      assert_redirected_to guide_assignments_path
    end
  end

  test "human resources cannot view monetary reports" do
    sign_out @admin
    sign_in User.create!(name: "HR", email: "weekly-report-hr@example.test",
      password: "password123", role: :recursos_humanos)
    get guide_assignments_path
    assert_redirected_to root_path
  end
end
