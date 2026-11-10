require "test_helper"

class SaraManualAssignmentTest < ActiveSupport::TestCase
  setup do
    @skills = %w[ClassIV Busguide Computer address_Sarapiqui].index_with do |name|
      Skill.find_or_create_by!(name: name)
    end
    @skills["Roll de Sara"] = Skill.find_or_create_by!(name: "Roll de Sara")
    CompensationRate.find_or_create_by!(code: "guide_regular",
      effective_at: Time.utc(2020, 1, 1)) do |rate|
      rate.amount_cents = 5_000
    end
    CompensationDiscountRule.find_or_create_by!(code: "second_sara",
      effective_at: Time.utc(2020, 1, 1)) do |rule|
      rule.percent = 20
    end
    @actor = User.create!(name: "Sara operator test",
      email: "sara-operator-test@example.test", password: "password123",
      role: :operador)
    @day = WorkDay.create!(date: Date.current + 45.days, status: :generated)
  end

  test "only active priority six reserve can fill a pending Sara slot" do
    reserve = guide("Sara reserve", 6, active: false,
      skills: %w[ClassIV address_Sarapiqui])
    slot = create_slot("Sara-3&4", %w[ClassIV])

    assert_raises(SaraManualAssignment::InvalidSelection) do
      service.call(slot_id: slot.id, guide_id: reserve.id, actor: @actor)
    end
    reserve.update!(active: true)
    selected = service.call(slot_id: slot.id, guide_id: reserve.id, actor: @actor)

    assert_equal reserve, selected
    assert reserve.reload.active?
    assert_equal "Sara-3&4", @day.guide_days.find_by!(guide: reserve).location
    assert @day.guide_days.find_by!(guide: reserve).worked?
    assert_equal 1, CompensationAssignment.joins(:departure)
      .where(guide: reserve, departures: { work_day_id: @day.id }).active.count
    assert_empty @day.roll_coverage_errors
    assert AuditLog.exists?(action: "assign_sara_guide", work_day: @day)
    assert_raises(SaraManualAssignment::InvalidSelection) do
      service.call(slot_id: slot.id, guide_id: reserve.id, actor: @actor)
    end
  end

  test "a Sara guide can fill PM as a second outing without moving the first" do
    sara = guide("Sara double outing", 5,
      skills: ["ClassIV", "Roll de Sara"])
    sara_slot = create_slot("Sara-3&4", %w[ClassIV])
    pm_slot = create_slot("PM", %w[ClassIV])
    service.call(slot_id: sara_slot.id, guide_id: sara.id, actor: @actor)

    assert service.candidates_for(pm_slot).any? do |candidate|
      candidate.guide == sara && candidate.kind == :second_outing
    end
    service.call(slot_id: pm_slot.id, guide_id: sara.id, actor: @actor)

    assert_equal "Sara-3&4", @day.guide_days.find_by!(guide: sara).reload.location
    rows = CompensationAssignment.joins(:departure)
      .where(guide: sara, departures: { work_day_id: @day.id })
      .order("departures.starts_at ASC")
    assert_equal %w[Sara-3&4 PM], rows.map { |row| row.departure.location }
    assert_equal 20, rows.last.compensation_lines.find_by!(code: "guide_regular").discount_percent
    assert_equal 2, RollFairnessPolicy.roll_worked_days_for_guide(sara,
      before_date: @day.date + 1.day)
    assert_empty @day.roll_coverage_errors
    assert AuditLog.exists?(action: "assign_sara_second_outing", work_day: @day)
  end

  test "resetting the roll cancels both Sara and the added PM outing" do
    sara = guide("Sara reset guide", 5,
      skills: ["ClassIV", "Roll de Sara"])
    sara_slot = create_slot("Sara-3&4", %w[ClassIV])
    pm_slot = create_slot("PM", %w[ClassIV])
    service.call(slot_id: sara_slot.id, guide_id: sara.id, actor: @actor)
    service.call(slot_id: pm_slot.id, guide_id: sara.id, actor: @actor)

    @day.reset_roll!

    assert @day.reload.draft?
    assert @day.guide_days.find_by!(guide: sara).reload.standby?
    assert_equal %w[canceled canceled], CompensationAssignment.joins(:departure)
      .where(guide: sara, departures: { work_day_id: @day.id })
      .order("departures.starts_at ASC").pluck(:status)
    assert_equal 0, RollFairnessPolicy.roll_worked_days_for_guide(sara,
      before_date: @day.date + 1.day)
  end

  test "removing the first Sara assignment also cancels its PM second outing" do
    sara = guide("Sara removed guide", 5,
      skills: ["ClassIV", "Roll de Sara"])
    sara_slot = create_slot("Sara-3&4", %w[ClassIV])
    pm_slot = create_slot("PM", %w[ClassIV])
    service.call(slot_id: sara_slot.id, guide_id: sara.id, actor: @actor)
    service.call(slot_id: pm_slot.id, guide_id: sara.id, actor: @actor)

    @day.guide_days.find_by!(guide: sara).update!(status: :standby,
      location: nil, role_primary: nil, role_secondary: nil)

    assert_equal %w[canceled canceled], CompensationAssignment.joins(:departure)
      .where(guide: sara, departures: { work_day_id: @day.id })
      .order("departures.starts_at ASC").pluck(:status)
    assert_equal 0, RollFairnessPolicy.roll_worked_days_for_guide(sara,
      before_date: @day.date + 1.day)
    assert_equal ["Sara-3&4: falta 1 puesto por cubrir", "PM: falta 1 puesto por cubrir"],
      @day.roll_coverage_errors
  end

  test "second outing is rolled back when the discount cannot be priced" do
    sara = guide("Sara missing discount", 5,
      skills: ["ClassIV", "Roll de Sara"])
    sara_slot = create_slot("Sara-3&4", %w[ClassIV])
    pm_slot = create_slot("PM", %w[ClassIV])
    service.call(slot_id: sara_slot.id, guide_id: sara.id, actor: @actor)
    CompensationDiscountRule.where(code: "second_sara").delete_all

    assert_raises(SaraManualAssignment::InvalidSelection) do
      service.call(slot_id: pm_slot.id, guide_id: sara.id, actor: @actor)
    end

    assert_equal 1, CompensationAssignment.joins(:departure)
      .where(guide: sara, departures: { work_day_id: @day.id }).count
    assert_equal ["PM: falta 1 puesto por cubrir"], @day.roll_coverage_errors
  end

  test "a specialist slot accepts an available qualified guide without Sara roll" do
    specialist = guide("Qualified bus guide", 2,
      skills: %w[ClassIV Busguide Computer])
    slot = create_slot("PM", %w[ClassIV Busguide Computer])

    assert_includes service.candidates_for(slot).map { |candidate| candidate.guide.id },
      specialist.id
    service.call(slot_id: slot.id, guide_id: specialist.id, actor: @actor)

    assert_equal "PM", @day.guide_days.find_by!(guide: specialist).location
    assert_empty @day.roll_coverage_errors
  end

  test "operator can add multiple bus guides to Sara and PM" do
    first = guide("First extra bus guide", 2,
      skills: %w[ClassIV Busguide])
    second = guide("Second extra bus guide", 3,
      skills: %w[ClassIV Busguide])
    pm = guide("PM extra bus guide", 3,
      skills: %w[ClassIV Busguide])

    assert_includes service.extra_bus_candidates_for("Sara-3&4")
      .map { |candidate| candidate.guide.id }, first.id
    service.add_bus_guide(location: "Sara-3&4", guide_id: first.id, actor: @actor)
    service.add_bus_guide(location: "Sara-3&4", guide_id: second.id, actor: @actor)
    service.add_bus_guide(location: "PM", guide_id: pm.id, actor: @actor)

    assert_equal 2, @day.location_slots.where(location: "Sara-3&4").count
    assert_equal 1, @day.location_slots.where(location: "PM").count
    assert_equal 3, @day.reload.guides_requested
    assert_equal "Bus Guide & Towels",
      @day.guide_days.find_by!(guide: first).role_secondary
    assert CompensationAssignment.joins(:departure)
      .where(guide: first, departures: { work_day_id: @day.id }).first.bus_guide?
    assert_empty @day.roll_coverage_errors

    assert_raises(SaraManualAssignment::InvalidSelection) do
      service.add_bus_guide(location: "PM", guide_id: first.id, actor: @actor)
    end
    assert_equal 3, @day.location_slots.count
  end

  test "unqualified reserve and day off guide are rejected" do
    unqualified = guide("Reserve without Sarapiqui address", 6,
      active: false, skills: %w[ClassIV])
    unavailable = guide("Sara day off", 5,
      skills: ["ClassIV", "Roll de Sara"])
    @day.guide_days.create!(guide: unavailable, status: :day_off)
    slot = create_slot("Sara-3&4", %w[ClassIV])

    assert_empty service.candidates_for(slot)
    [unqualified, unavailable].each do |guide_record|
      assert_raises(SaraManualAssignment::InvalidSelection) do
        service.call(slot_id: slot.id, guide_id: guide_record.id, actor: @actor)
      end
    end
    assert_equal 0, @day.assigned_roll_count
  end

  private

  def service
    SaraManualAssignment.new(@day)
  end

  def guide(name, priority, active: true, skills:)
    Guide.create!(name: name, priority: priority, active: active,
      pay_category: "freelance_regular",
      skills: skills.map { |name| @skills.fetch(name) })
  end

  def create_slot(location, skills)
    @day.location_slots.create!(location: location).tap do |slot|
      slot.skills = skills.map { |name| @skills.fetch(name) }
    end
  end
end
