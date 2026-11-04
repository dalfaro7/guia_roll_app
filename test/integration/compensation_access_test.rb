require "test_helper"
require_relative "../../db/migrate/20261103000000_create_compensation_system"

class CompensationAccessTest < ActionDispatch::IntegrationTest
  setup do
    missing_rates = CreateCompensationSystem::INITIAL_RATES.reject do |code, _|
      CompensationRate.exists?(code: code.to_s)
    end
    if missing_rates.any?
      CompensationRate.insert_all!(
        missing_rates.map do |code, cents|
          { code: code.to_s, amount_cents: cents,
            effective_at: Time.utc(2020, 1, 1),
            created_at: Time.current, updated_at: Time.current }
        end
      )
    end
    { "second_sara" => 20, "second_other" => 30 }.each do |code, percent|
      next if CompensationDiscountRule.exists?(code: code)

      CompensationDiscountRule.insert!({ code: code, percent: percent,
        effective_at: Time.utc(2020, 1, 1), created_at: Time.current,
        updated_at: Time.current })
    end
    @day = WorkDay.create!(date: Date.current + 2.days, guides_requested: 0)
    @day.departures.create!(label: "Balsa", location: "Balsa",
      starts_at: Time.find_zone!("America/Costa_Rica").local(
        @day.date.year, @day.date.month, @day.date.day, 6))
  end

  def user(role)
    User.create!(name: "Test #{role}", email: "#{role}-compensation@example.com",
      password: "password123", role: role)
  end

  def confirmation_token_for(departure)
    get confirm_cancel_work_day_departure_path(@day, departure)
    assert_response :success
    assert_select "h1", /¿Está seguro de esta acción?/
    css_select("input[name='confirmation_token']").first["value"]
  end

  test "admin can open daily valuation and tariff pages" do
    sign_in user(:admin)
    get work_day_compensation_path(@day)
    assert_response :success
    assert_select "h1", /Valoración/
    get compensation_rates_path
    assert_redirected_to unlock_compensation_rates_path
    post verify_compensation_rates_key_path, params: { password: "admin" }
    assert_redirected_to compensation_rates_path
    get compensation_rates_path
    assert_response :success
    assert_no_match(/Segunda salida en otros destinos/, response.body)
    get compensation_profiles_path
    assert_response :success
    get drivers_path
    assert_response :success
    get compensation_reports_path
    assert_response :success
    get compensation_settlements_path
    assert_response :success

    guide = Guide.create!(name: "Statement guide", priority: 3,
      active: true, pay_category: "freelance_regular")
    @day.departures.first.compensation_assignments.create!(
      guide: guide, role_code: "river_guide")
    @day.departures.create!(label: "Sara clase 3", location: "Sara-3",
      starts_at: Time.find_zone!("America/Costa_Rica").local(
        @day.date.year, @day.date.month, @day.date.day, 10))
      .compensation_assignments.create!(guide: guide, role_code: "river_guide")
    Compensation::RepriceDay.call(@day)
    get work_day_compensation_path(@day)
    assert_response :success
    assert_select "h2", "Total diario por persona"
    assert_select "tr[data-operating-section='Sara-3&4']", text: /1 asignación/
    balsa_id = @day.departures.find_by!(location: "Balsa").id
    sara_id = @day.departures.find_by!(location: "Sara-3").id
    assert_operator response.body.index("id=\"departure-#{balsa_id}\""), :<,
      response.body.index("id=\"departure-#{sara_id}\"")
    priced_assignments = @day.departures.reload.flat_map { |departure|
      departure.compensation_assignments.to_a
    }
    assert_equal 9_000, priced_assignments.sum(&:total_cents),
      priced_assignments.map { |assignment|
        [assignment.id, assignment.pricing_error, assignment.compensation_lines.pluck(:code, :amount_cents)]
      }.inspect
    settlement = CompensationSettlement.find_by!(guide: guide)
    get compensation_settlement_path(settlement)
    assert_response :success
    assert_select "td", text: /Balsa/
  end

  test "accounting sees valuation but cannot change a departure" do
    sign_in user(:contabilidad)
    get work_day_compensation_path(@day)
    assert_response :success
    assert_select "a", text: "Cancelar salida", count: 0
    patch work_day_departure_path(@day, @day.departures.first), params: {
      departure: { status: "canceled" }
    }
    assert_redirected_to root_path
    assert_equal "scheduled", @day.departures.first.reload.status
  end

  test "human resources cannot see economic data" do
    sign_in user(:recursos_humanos)
    get work_day_compensation_path(@day)
    assert_redirected_to root_path
    get compensation_settlements_path
    assert_redirected_to root_path
  end

  test "only admin can schedule a future second outing discount" do
    effective_at = (Time.current + 1.day).in_time_zone("America/Costa_Rica")
      .strftime("%Y-%m-%dT%H:%M")
    params = { compensation_discount_rule: {
      code: "second_sara", percent: "25", effective_at: effective_at
    } }

    sign_in user(:contabilidad)
    post compensation_discount_rules_path, params: params
    assert_not CompensationDiscountRule.exists?(code: "second_sara", percent: 25)

    sign_out :user
    sign_in user(:admin)
    post verify_compensation_rates_key_path, params: { password: "admin" }
    post compensation_discount_rules_path, params: params
    assert_redirected_to compensation_rates_path
    rule = CompensationDiscountRule.find_by!(code: "second_sara", percent: 25)
    assert AuditLog.exists?(action: "create_compensation_discount_rule",
      auditable_id: rule.id)
  end

  test "tariff key protects viewing and saving even for an admin" do
    sign_in user(:admin)
    get compensation_rates_path
    assert_redirected_to unlock_compensation_rates_path

    post compensation_discount_rules_path, params: {
      compensation_discount_rule: {
        code: "second_sara", percent: 25,
        effective_at: (Time.current + 1.day).strftime("%Y-%m-%dT%H:%M")
      }
    }
    assert_redirected_to unlock_compensation_rates_path

    post verify_compensation_rates_key_path, params: { password: "incorrecta" }
    assert_redirected_to unlock_compensation_rates_path
    get compensation_rates_path
    assert_redirected_to unlock_compensation_rates_path

    post verify_compensation_rates_key_path, params: { password: "admin" }
    assert_redirected_to compensation_rates_path
    get compensation_rates_path
    assert_response :success
  end

  test "valuation shows four outings without editable schedules" do
    sign_in user(:operador)

    assert_no_difference "Departure.count" do
      get work_day_compensation_path(@day)
    end
    assert_response :success
    assert_select "tr[data-operating-section]", 4
    assert_select "tr[data-operating-section='Balsa'] a[href='#departure-#{@day.departures.first.id}']", text: "Editar"
    assert_select "input[type='time']", 0
    assert_select "a[href='#{confirm_cancel_work_day_departure_path(@day, @day.departures.first)}']", text: "Cancelar salida"
    assert_select "form[action='#{work_day_departure_path(@day, @day.departures.first)}']", 0
    assert_no_match(/Crear otra salida|Configurar horario/, response.body)
  end

  test "Tour Leader in the team schedule creates the matching TL valuation" do
    guide = Guide.create!(name: "Team TL", priority: 3,
      active: true, pay_category: "freelance_regular")
    @day.update!(status: :generated)
    guide_day = GuideDay.create!(guide: guide, work_day: @day,
      status: :worked, location: "Balsa", role_primary: "River Guide")
    assignment = CompensationAssignment.find_by!(guide_day: guide_day)

    sign_in user(:operador)
    get work_day_path(@day)
    assert_select "select[name='roles[#{guide_day.id}][role_secondary]'] option[value='Tour Leader']", text: /TL/
    assert_select "select[name='roles[#{guide_day.id}][role_secondary]'] option[value='Head Guide']", text: /HG/

    patch update_roles_work_day_path(@day), params: {
      roles: { guide_day.id.to_s => { role_primary: "River Guide",
        role_secondary: "Tour Leader", location: "Balsa" } }
    }
    assert_redirected_to work_day_path(@day)
    assert_equal "Tour Leader", guide_day.reload.role_secondary
    assert_equal "tl_balsa", assignment.reload.role_code

    get work_day_compensation_path(@day)
    assert_select "td", text: /TL Balsa/
  end

  test "Balsa offers only Balsa leader rates and rejects a Sara rate" do
    guide = Guide.create!(name: "Leader by location", priority: 3,
      active: true, pay_category: "freelance_regular")
    assignment = @day.departures.first.compensation_assignments.create!(
      guide: guide, role_code: "hg_balsa")
    sign_in user(:operador)

    get work_day_compensation_path(@day)
    assert_select "form[action='#{work_day_compensation_assignment_path(@day, assignment)}']" do
      assert_select "option[value='hg_balsa']"
      assert_select "option[value='tl_balsa']"
      assert_select "option[value='hg_sara']", count: 0
      assert_select "option[value='tl_sara']", count: 0
    end

    patch work_day_compensation_assignment_path(@day, assignment), params: {
      compensation_assignment: { role_code: "hg_sara", photo_task: "none",
        status: "planned", principal_photographer: "0", also_drives: "0",
        bus_guide: "0" }
    }
    assert_redirected_to work_day_compensation_path(@day)
    assert_equal "hg_balsa", assignment.reload.role_code

    sara = @day.departures.create!(label: "Sara clase 3", location: "Sara-3",
      starts_at: Departure.fixed_start_for(@day.date, "Sara-3"))
    sara_assignment = sara.compensation_assignments.create!(guide: guide,
      role_code: "hg_sara")
    assert sara_assignment.valid?
    assert_not sara.compensation_assignments.build(guide: guide,
      role_code: "hg_balsa").valid?
  end

  test "changing the team role updates a manually valued leader" do
    guide = Guide.create!(name: "Manual leader", priority: 3,
      active: true, pay_category: "freelance_regular")
    @day.update!(status: :generated)
    guide_day = GuideDay.create!(guide: guide, work_day: @day,
      status: :worked, location: "Balsa", role_primary: "River Guide")
    assignment = CompensationAssignment.find_by!(guide_day: guide_day)

    sign_in user(:operador)
    patch work_day_compensation_assignment_path(@day, assignment), params: {
      return_to: "schedule",
      compensation_assignment: { role_code: "tl_balsa", photo_task: "none",
        status: "planned", principal_photographer: "0", also_drives: "0",
        bus_guide: "0" }
    }
    assert_equal "Tour Leader", guide_day.reload.role_secondary

    patch update_roles_work_day_path(@day), params: {
      roles: { guide_day.id.to_s => { role_primary: "River Guide",
        role_secondary: "Head Guide", location: "Balsa" } }
    }
    assert_redirected_to work_day_path(@day)
    assert_equal "Head Guide", guide_day.reload.role_secondary
    assert_equal "hg_balsa", assignment.reload.role_code
    assert_equal "manual", assignment.source
    assert AuditLog.exists?(action: "sync_compensation_from_schedule",
      auditable_id: assignment.id)
  end

  test "operator chooses TL and bonus options from the scheduling page" do
    guide = Guide.create!(name: "Scheduled TL", priority: 3,
      active: true, pay_category: "freelance_regular")
    @day.update!(status: :generated)
    guide_day = GuideDay.create!(guide: guide, work_day: @day,
      status: :worked, location: "Balsa", role_primary: "River Guide")
    assignment = CompensationAssignment.find_by!(guide_day: guide_day)

    sign_in user(:operador)
    get work_day_path(@day)
    assert_response :success
    assert_select "#day-compensation form[action='#{work_day_compensation_assignment_path(@day, assignment)}']" do
      assert_select "select[name='compensation_assignment[role_code]'] option[value='tl_balsa']"
      assert_select "select[name='compensation_assignment[role_code]'] option[value='hg_balsa']"
      assert_select "select[name='compensation_assignment[photo_task]'] option[value='take_and_send']"
    end

    patch work_day_compensation_assignment_path(@day, assignment), params: {
      return_to: "schedule",
      compensation_assignment: { role_code: "tl_balsa", photo_task: "none",
        status: "planned", principal_photographer: "0", also_drives: "0",
        bus_guide: "0" }
    }
    assert_redirected_to work_day_path(@day, anchor: "day-compensation")
    assert_equal "tl_balsa", assignment.reload.role_code
    assert_equal "manual", assignment.source
    assert_equal "River Guide", guide_day.reload.role_primary
    assert_equal "Tour Leader", guide_day.role_secondary

    get work_day_compensation_path(@day)
    assert_select "td", text: /TL Balsa/
  end

  test "operator can designate a different principal photographer" do
    first_guide = Guide.create!(name: "Photo principal", priority: 3,
      active: true, pay_category: "freelance_regular")
    second_guide = Guide.create!(name: "Photo second", priority: 3,
      active: true, pay_category: "freelance_regular")
    departure = @day.departures.first
    first = departure.compensation_assignments.create!(guide: first_guide,
      role_code: "photographer", principal_photographer: true)
    second = departure.compensation_assignments.create!(guide: second_guide,
      role_code: "photographer")

    sign_in user(:operador)
    patch work_day_compensation_assignment_path(@day, second), params: {
      compensation_assignment: {
        role_code: "photographer", photo_task: "none", status: "planned",
        principal_photographer: "1", also_drives: "0", bus_guide: "0"
      }
    }
    assert_redirected_to work_day_compensation_path(@day)
    assert_not first.reload.principal_photographer?
    assert second.reload.principal_photographer?
    assert AuditLog.exists?(action: "transfer_principal_photographer",
      auditable_id: first.id)
  end

  test "operator cannot change a departure time even through a direct request" do
    departure = @day.departures.first
    original_start = departure.starts_at
    sign_in user(:operador)

    token = confirmation_token_for(departure)
    patch work_day_departure_path(@day, departure), params: {
      departure: { status: "canceled", starts_at_time: "07:00" },
      confirmation_token: token
    }

    assert_redirected_to work_day_compensation_path(@day)
    assert_equal "scheduled", departure.reload.status
    assert_equal original_start, departure.starts_at
  end

  test "only scheduled departures can be canceled" do
    departure = @day.departures.first
    departure.update!(status: "completed")
    sign_in user(:operador)

    get confirm_cancel_work_day_departure_path(@day, departure)
    assert_redirected_to work_day_compensation_path(@day)
    assert_equal "completed", departure.reload.status
  end

  test "operator can cancel a scheduled outing before 20:00 and clear pending pay" do
    departure = @day.departures.first
    guide = Guide.create!(name: "Cancel test guide", priority: 3,
      active: true, pay_category: "freelance_regular")
    assignment = departure.compensation_assignments.create!(
      guide: guide, role_code: "river_guide")
    Compensation::RepriceDay.call(@day)
    assert_operator assignment.reload.total_cents, :>, 0
    original_start = departure.starts_at

    travel_to departure.starts_at + 13.hours + 59.minutes do
      sign_in user(:operador)
      patch work_day_departure_path(@day, departure), params: {
        departure: { status: "canceled" }
      }
      assert_equal "scheduled", departure.reload.status

      token = confirmation_token_for(departure)
      assert_select "a", text: "No, volver sin cambios"
      assert_select "strong", text: /1 asignación pendiente/
      patch work_day_departure_path(@day, departure), params: {
        departure: { status: "canceled" }, confirmation_token: token
      }
      assert_equal "canceled", departure.reload.status
      assert_equal original_start, departure.starts_at
      assert_equal "canceled", assignment.reload.status
      assert_equal 0, assignment.total_cents
    end
  end

  test "after 20:00 only admin can correct a departure with a reason" do
    departure = @day.departures.first
    travel_to departure.starts_at + 14.hours do
      sign_in user(:operador)
      patch work_day_departure_path(@day, departure), params: {
        departure: { status: "canceled" }
      }
      assert_equal "scheduled", departure.reload.status

      sign_out :user
      sign_in user(:admin)
      patch work_day_departure_path(@day, departure), params: {
        departure: { status: "canceled" }
      }
      assert_equal "scheduled", departure.reload.status

      token = confirmation_token_for(departure)
      patch work_day_departure_path(@day, departure), params: {
        departure: { status: "canceled" },
        confirmation_token: token,
        correction_reason: "Salida cancelada por operación"
      }
      assert_equal "canceled", departure.reload.status
      assert AuditLog.exists?(action: "update_departure", auditable_id: departure.id)
    end
  end
end
