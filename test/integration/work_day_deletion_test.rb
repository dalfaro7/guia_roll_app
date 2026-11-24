require "test_helper"

class WorkDayDeletionTest < ActionDispatch::IntegrationTest
  setup do
    @operator = User.create!(name: "Delete operator", email: "delete@example.test",
      password: "password123", role: :operador)
    @guide = Guide.create!(name: "Deletion guide", priority: 5, active: true,
      day_off_balance: 3)
    @day = WorkDay.create!(date: Date.tomorrow)
    @guide_day = @day.guide_days.find_by!(guide: @guide)
    sign_in @operator
  end

  test "deletes unvalued draft with notes and restores only its consumed balances" do
    @guide_day.update!(status: :day_off)
    other = WorkDay.create!(date: Date.tomorrow + 1.day)
    other_guide_day = other.guide_days.find_by!(guide: @guide)
    other_guide_day.update!(status: :day_off)
    note = @day.roll_notes.create!(created_by: @operator, note: "Test note",
      note_type: :observation, guide_days: [@guide_day])
    audit = AuditLog.create!(user: @operator, work_day: @day,
      action: "test", auditable_type: "WorkDay", auditable_id: @day.id)
    slot = @day.location_slots.create!(location: "Sara-3&4")
    slot.skills << Skill.find_or_create_by!(name: "ClassIV")
    @day.work_day_versions.create!(snapshot: { event: "test" })

    assert_difference "WorkDay.count", -1 do
      delete delete_with_reset_work_day_path(@day)
    end
    assert_redirected_to work_days_path
    assert_equal 2, @guide.reload.day_off_balance
    assert other_guide_day.reload.day_off_consumed?
    assert_not RollNote.exists?(note.id)
    assert_not SlotSkill.exists?(location_slot_id: slot.id)
    assert_nil audit.reload.work_day_id
  end

  test "deletes a future generated plan and reverses guide and transport amounts" do
    @guide_day.update!(status: :day_off)
    @day.update!(status: :generated)
    departure = @day.departures.create!(label: "Balsa", location: "Balsa",
      starts_at: Departure.fixed_start_for(@day.date, "Balsa"))
    assignment = departure.compensation_assignments.create!(guide: @guide,
      role_code: "river_guide", status: "planned")
    line = assignment.compensation_lines.create!(code: "guide_regular",
      rate_cents: 5_000, amount_cents: 5_000, applied_at: Time.current)
    week_start = Compensation::SettlementService.week_start(@day.date)
    settlement = CompensationSettlement.create!(guide: @guide,
      week_start: week_start, week_end: week_start + 6.days,
      amount_cents: 5_000)
    item = settlement.compensation_settlement_items.create!(
      compensation_assignment: assignment, amount_cents: 5_000,
      details: { date: @day.date.iso8601 })
    driver = Driver.create!(name: "Deletion driver", payment_mode: "per_trip")
    driver_assignment = departure.compensation_assignments.create!(driver: driver,
      role_code: "driver_per_trip", status: "planned")
    driver_line = driver_assignment.compensation_lines.create!(code: "driver_per_trip",
      rate_cents: 2_000, amount_cents: 2_000, applied_at: Time.current)
    driver_settlement = CompensationSettlement.create!(driver: driver,
      week_start: week_start, week_end: week_start + 6.days,
      amount_cents: 2_000)
    driver_item = driver_settlement.compensation_settlement_items.create!(
      compensation_assignment: driver_assignment, amount_cents: 2_000,
      details: { date: @day.date.iso8601 })
    company = TransportCompany.create!(name: "Deletion transport company")
    bus = Bus.create!(alias: "Deletion bus", plate: "DEL-100", capacity: 15,
      transport_company: company)
    transport = @day.bus_assignments.create!(bus: bus, location: "Balsa",
      seats_assigned: 10)
    assert_equal 12_000, transport.cost_cents

    get work_day_path(@day)
    assert_select "button", text: "Eliminar programación"
    assert_difference({ "WorkDay.count" => -1,
        "CompensationAssignment.count" => -2,
        "CompensationSettlementItem.count" => -2,
        "BusAssignment.count" => -1 }) do
      delete delete_with_reset_work_day_path(@day)
    end

    assert_redirected_to work_days_path
    assert_equal 3, @guide.reload.day_off_balance
    assert_not CompensationLine.exists?(line.id)
    assert_not CompensationLine.exists?(driver_line.id)
    assert_not CompensationSettlement.exists?(settlement.id)
    assert_not CompensationSettlement.exists?(driver_settlement.id)
    assert_not Departure.exists?(departure.id)
    assert_not BusAssignment.exists?(transport.id)
    assert_not CompensationSettlementItem.exists?(item.id)
    assert_not CompensationSettlementItem.exists?(driver_item.id)
  end

  test "keeps a future generated plan when its week has a closed payment" do
    @day.update!(status: :generated)
    week_start = Compensation::SettlementService.week_start(@day.date)
    settlement = CompensationSettlement.create!(guide: @guide,
      week_start: week_start, week_end: week_start + 6.days,
      closed_at: Time.current)

    assert_no_difference ["WorkDay.count", "CompensationSettlement.count"] do
      delete delete_with_reset_work_day_path(@day)
    end
    assert_redirected_to work_day_path(@day)
    assert_match(/pagos cerrados/, flash[:alert])
    assert CompensationSettlement.exists?(settlement.id)
  end

  test "keeps a generated plan that was previously published" do
    @day.update!(status: :generated)
    @day.work_day_versions.create!(snapshot: { event: "publish" })

    assert_no_difference "WorkDay.count" do
      delete delete_with_reset_work_day_path(@day)
    end
    assert_redirected_to work_day_path(@day)
    assert_match(/ya fue publicada/, flash[:alert])
  end

  test "keeps a generated plan with performed work" do
    @day.update!(status: :generated)
    departure = @day.departures.create!(label: "Balsa", location: "Balsa",
      starts_at: Departure.fixed_start_for(@day.date, "Balsa"))
    assignment = departure.compensation_assignments.create!(guide: @guide,
      role_code: "river_guide", status: "performed")

    assert_no_difference ["WorkDay.count", "CompensationAssignment.count"] do
      delete delete_with_reset_work_day_path(@day)
    end
    assert_redirected_to work_day_path(@day)
    assert_match(/trabajo o pagos realizados/, flash[:alert])
    assert CompensationAssignment.exists?(assignment.id)
  end

  %w[draft published].each do |state|
    test "protects economic dependencies in #{state} without changing equity or balances" do
      @guide_day.update!(status: :day_off)
      departure = @day.departures.create!(label: "Sara", location: "Sara-3&4",
        starts_at: Departure.fixed_start_for(@day.date, "Sara-3&4"))
      assignment = departure.compensation_assignments.create!(guide: @guide,
        guide_day: @guide_day, role_code: "river_guide")
      @day.update!(status: state)
      version = @day.work_day_versions.create!(snapshot: { event: "test" })
      before = @guide_day.attributes

      assert_no_difference ["WorkDay.count", "GuideDay.count", "CompensationAssignment.count"] do
        delete delete_with_reset_work_day_path(@day)
      end
      assert_redirected_to work_day_path(@day)
      assert_match(/no se puede eliminar/, flash[:alert])
      assert_equal before, @guide_day.reload.attributes
      assert_equal 2, @guide.reload.day_off_balance
      assert WorkDayVersion.exists?(version.id)
      assert CompensationAssignment.exists?(assignment.id)
      assert_equal state, @day.reload.status
    end

    test "HG cannot delete the shared #{state} operation" do
      @day.update!(status: state)
      @operator.update!(role: :hg_sarapiqui)
      assert_no_difference ["WorkDay.count", "GuideDay.count"] do
        delete delete_with_reset_work_day_path(@day)
      end
      assert_redirected_to sara_work_days_path
      assert_equal state, @day.reload.status
    end
  end
end
