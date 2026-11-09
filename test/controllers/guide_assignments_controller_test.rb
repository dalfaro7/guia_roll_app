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
      assert_select "#guide-weekly-table tbody tr", count: 7
      assert_select "#operation-expenses-table tbody tr", count: 7
      assert_select "p", text: /04\/11\/2026.*10\/11\/2026/
      assert_select "[data-bs-toggle='modal']", count: 7
      assert_select "button[data-controller='weekly-print']", text: "Imprimir en rollo", count: 1
      assert_select "#weekly-roll-receipt .roll-receipt__day", count: 7
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
    CompensationRate.create!(code: "driver_la_fortuna", amount_cents: 3_000,
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
    other_guide = Guide.create!(name: "B Guide", priority: 2, active: true,
      pay_category: "freelance_regular")
    departure.compensation_assignments.create!(guide: other_guide,
      role_code: "river_guide", status: "performed")
    driver = Driver.create!(name: "A Driver", active: true, phone: "555-1003", transport_company: TransportCompany.create!(name: "Test Transport C"))
    departure.compensation_assignments.create!(driver: driver,
      role_code: "driver_la_fortuna", status: "performed")
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
      assert_select "#guide-weekly-table tbody tr", count: 7
      assert_select "#operation-expenses-table tbody tr", count: 7
      assert_select "#operation-expenses-table tbody tr", text: /#{paid_date.strftime("%d\/%m")}.*160[,.]00.*30[,.]00.*190[,.]00/
      assert_select "#operation-expenses-table tfoot", text: /Total semanal.*190[,.]00/
      assert_select "#driver-payments-table tbody tr", text: /A Driver.*Balsa mañana.*30[,.]00/
      assert_select "#driver-payments-table tfoot", text: /Total de choferes.*30[,.]00/
      assert_select "#driver-recipient-totals-table tbody tr", text: /A Driver.*30[,.]00/
      assert_select "#company-payments-table", count: 0
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

  test "the current week shows only elapsed days and excludes future assignments from its total" do
    travel_to @zone.local(2026, 11, 13, 12) do
      CompensationRate.create!(code: "guide_regular", amount_cents: 5_000,
        effective_at: Time.utc(2020, 1, 1))
      today = WorkDay.create!(date: Date.new(2026, 11, 13), guides_requested: 0)
      future = WorkDay.create!(date: Date.new(2026, 11, 15), guides_requested: 0)
      [[today, "completed", "performed"], [future, "scheduled", "planned"]].each do |work_day, departure_status, assignment_status|
        departure = work_day.departures.create!(label: "Balsa", location: "Balsa",
          starts_at: @zone.local(work_day.date.year, work_day.date.month, work_day.date.day, 6),
          status: departure_status)
        departure.compensation_assignments.create!(guide: @guide,
          role_code: "river_guide", status: assignment_status)
        Compensation::RepriceDay.call(work_day)
      end
      Compensation::SettlementService.refresh_for(today)
      assert_equal 10_000, CompensationSettlement.find_by!(guide: @guide,
        week_start: Date.new(2026, 11, 11)).amount_cents

      get guide_assignments_path, params: { guide_id: @guide.id, week: "2026-11-13" }
      assert_response :success
      assert_select "#guide-weekly-table tbody tr", count: 3
      assert_select "#operation-expenses-table tbody tr", count: 3
      assert_select "#operation-expenses-table tfoot", text: /Total hasta hoy.*50[,.]00/
      assert_select "#weekly-day-20261115", count: 0
      assert_select "#weekly-roll-receipt .roll-receipt__day", count: 3
      assert_select "#weekly-roll-receipt .roll-receipt__total", text: /Total hasta hoy.*50[,.]00/
      assert_select "#weekly-roll-receipt .roll-receipt__line", text: /Guía regular.*50[,.]00/
      assert_select "#weekly-roll-receipt", text: /Los importes planificados de hoy son provisionales/
      assert_select "p", text: /11\/11\/2026.*13\/11\/2026/
      assert_select "tfoot", text: /Total hasta hoy.*50[,.]00/
      assert_select "input#week[max='2026-11-13']", count: 1
      assert_select "span", text: /Quincena.*13\/11\/2026/
      assert_select "span", text: /Mes.*13\/11\/2026/
    end
  end

  test "today shows planned personnel and assigned transport as provisional expenses" do
    travel_to @zone.local(2026, 11, 13, 12) do
      CompensationRate.create!(code: "guide_regular", amount_cents: 5_000,
        effective_at: Time.utc(2020, 1, 1))
      day = WorkDay.create!(date: Date.new(2026, 11, 13), guides_requested: 0)
      departure = day.departures.create!(label: "Balsa", location: "Balsa",
        starts_at: @zone.local(2026, 11, 13, 9, 20), status: "scheduled")
      departure.compensation_assignments.create!(guide: @guide,
        role_code: "river_guide", status: "planned")
      company = TransportCompany.create!(name: "Transporte del día")
      bus = Bus.create!(transport_company: company, alias: "Bus de hoy",
        plate: "HOY-13", capacity: 20)
      driver = Driver.create!(name: "Diego de prueba", phone: "555-2013",
        transport_company: company)
      BusAssignment.create!(bus: bus, driver: driver, work_day: day, location: "Balsa",
        seats_assigned: 10)
      Compensation::RepriceDay.call(day)

      get guide_assignments_path, params: { guide_id: @guide.id, week: day.date.iso8601 }
      assert_response :success
      assert_select "#guide-weekly-table tbody tr", text: /13\/11.*50[,.]00/
      assert_select "#operation-expenses-table tbody tr", text: /13\/11.*Provisional.*50[,.]00.*0[,.]00.*120[,.]00.*170[,.]00/
      assert_select "#operation-expenses-table tfoot", text: /Total hasta hoy.*170[,.]00/
      assert_select "#operation-expenses-table th", text: "Transporte"
      assert_select "#company-payments-table tbody tr", text: /Transporte del día.*Balsa.*Bus de hoy.*Chofer: Diego de prueba.*120[,.]00/
      assert_select "#company-payments-table tfoot", text: /Total de empresas de transporte.*120[,.]00/
      assert_select "#company-recipient-totals-table tbody tr", text: /Transporte del día.*120[,.]00/
      assert_select "#driver-payments-table", count: 0
    end
  end

  test "paid operation expenses keep the settled amount" do
    date = Date.current + 1.day
    report_date = Compensation::SettlementService.week_start(date) + 7.days
    CompensationRate.create!(code: "guide_regular", amount_cents: 5_000,
      effective_at: Time.utc(2020, 1, 1))
    work_day = WorkDay.create!(date: date, guides_requested: 0)
    departure = work_day.departures.create!(label: "Balsa", location: "Balsa",
      starts_at: @zone.local(date.year, date.month, date.day, 6), status: "completed")
    assignment = departure.compensation_assignments.create!(guide: @guide,
      role_code: "river_guide", status: "performed")
    Compensation::RepriceDay.call(work_day)

    travel_to @zone.local(report_date.year, report_date.month, report_date.day, 12) do
      CompensationCloseDueDaysJob.perform_now
      settlement = CompensationSettlement.find_by!(guide: @guide,
        week_start: Compensation::SettlementService.week_start(date))
      settlement.mark_paid!(@admin)
      assignment.compensation_lines.find_by!(code: "guide_regular")
        .update_columns(amount_cents: 9_000)

      get guide_assignments_path, params: { week: date.iso8601 }
      assert_response :success
      assert_select "#operation-expenses-table tbody tr", text: /#{Regexp.escape(date.strftime("%d/%m"))}.*50[,.]00/
      assert_select "#operation-expenses-table tfoot", text: /Total semanal.*50[,.]00/
      assert_select "#weekly-roll-receipt .roll-receipt__total", text: /Total semanal.*50[,.]00/
      assert_select "#weekly-roll-receipt .roll-receipt__line", text: /Guía regular.*50[,.]00/
    end
  end

  test "a future week cannot be queried" do
    travel_to @zone.local(2026, 11, 11, 12) do
      get guide_assignments_path, params: { week: "2026-11-17" }
      assert_redirected_to guide_assignments_path
      get guide_assignments_path, params: { week: "2026-11-18" }
      assert_redirected_to guide_assignments_path
    end
  end

  test "operator can open weekly reports from navigation" do
    sign_out @admin
    sign_in User.create!(name: "Operador", email: "weekly-report-operator@example.test",
      password: "password123", role: :operador)
    get guide_assignments_path
    assert_response :success
    assert_select "h1", "Reportes semanales"
    assert_select "nav a[href='#{guide_assignments_path}']", text: "Reportes semanales"
    work_day = WorkDay.create!(date: Date.current + 2.days, guides_requested: 0)
    get work_day_path(work_day)
    assert_response :success
    assert_select "aside.day-sidebar-left a[href='#{guide_assignments_path}']",
      text: "Reportes semanales"
  end

  test "human resources cannot view monetary reports" do
    sign_out @admin
    sign_in User.create!(name: "HR", email: "weekly-report-hr@example.test",
      password: "password123", role: :recursos_humanos)
    get guide_assignments_path
    assert_redirected_to root_path
  end
end
