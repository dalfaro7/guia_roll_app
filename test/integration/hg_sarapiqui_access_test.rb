require "test_helper"

class HgSarapiquiAccessTest < ActionDispatch::IntegrationTest
  setup do
    @hg = User.create!(name: "HG Sarapiquí test",
      email: "hg-sara@example.test", password: "password123",
      role: :hg_sarapiqui)
    @class_iv = Skill.find_or_create_by!(name: "ClassIV")
    @residence = Skill.find_or_create_by!(name: "address_Sarapiqui")
    @busguide = Skill.find_or_create_by!(name: "Busguide")
    @sara_roll = Skill.find_or_create_by!(name: "Roll de Sara")
    CompensationRate.find_or_create_by!(code: "guide_regular",
      effective_at: Time.utc(2020, 1, 1)) do |rate|
      rate.amount_cents = 5_000
    end
    @day = WorkDay.create!(date: Date.current + 52.days)
    sign_in @hg
  end

  test "HG sees only Sara routes and cannot publish or edit general operation" do
    @day.update!(status: :generated)

    get root_path
    assert_redirected_to sara_work_days_path
    get sara_work_days_path
    assert_response :success
    assert_select "a[href='#{sara_guides_path}']", minimum: 1
    assert_select "a[href='#{work_days_path}']", count: 0

    get sara_operation_work_day_path(@day)
    assert_response :success

    get work_day_path(@day)
    assert_redirected_to sara_work_days_path
    get guides_path
    assert_redirected_to sara_work_days_path
    get work_day_compensation_path(@day)
    assert_redirected_to sara_work_days_path
    get user_roles_path
    assert_redirected_to sara_work_days_path
    get new_user_registration_path
    assert_redirected_to sara_work_days_path

    post publish_work_day_path(@day)
    assert_redirected_to sara_work_days_path
    assert @day.reload.generated?
  end

  test "HG opens existing unpublished date or creates a new draft" do
    get sara_operation_work_day_path(@day)
    assert_response :success
    assert_select "#sara-priority-five-availability", count: 1

    post create_sara_work_days_path, params: { date: @day.date.iso8601 }
    assert_redirected_to sara_operation_work_day_path(@day)

    date = @day.date + 1.day
    assert_difference "WorkDay.count", 1 do
      post create_sara_work_days_path, params: { date: date.iso8601 }
    end
    created = WorkDay.find_by!(date: date)
    assert created.draft?
    assert_redirected_to sara_operation_work_day_path(created)

    @day.update!(status: :published)
    get sara_operation_work_day_path(@day)
    assert_redirected_to sara_work_days_path
    post create_sara_work_days_path, params: { date: @day.date.iso8601 }
    assert_redirected_to sara_work_days_path

    assert_no_difference "WorkDay.count" do
      post create_sara_work_days_path,
        params: { date: (Date.current - 1.day).iso8601 }
    end
    assert_redirected_to sara_work_days_path
  end

  test "HG changes only priority five availability and restores unused day off balance" do
    guide = Guide.create!(name: "Sara availability five", priority: 5,
      active: true, pay_category: "freelance_regular",
      day_off_balance: 2, skills: [@class_iv, @sara_roll])
    guide_day = @day.guide_days.create!(guide: guide, status: :standby)
    other = Guide.create!(name: "Balsa priority two", priority: 2,
      active: true, pay_category: "freelance_regular")
    other_day = @day.guide_days.create!(guide: other, status: :standby)

    patch update_sara_availability_work_day_path(@day),
      params: { guide_day_id: guide_day.id, status: "day_off" }
    assert_redirected_to sara_operation_work_day_path(@day)
    assert guide_day.reload.day_off?
    assert_equal 1, guide.reload.day_off_balance

    patch update_sara_availability_work_day_path(@day),
      params: { guide_day_id: guide_day.id, status: "standby" }
    assert guide_day.reload.standby?
    assert_equal 2, guide.reload.day_off_balance
    assert_not guide_day.day_off_consumed?

    patch update_sara_availability_work_day_path(@day),
      params: { guide_day_id: guide_day.id, status: "penalized" }
    assert guide_day.reload.standby?

    patch update_sara_availability_work_day_path(@day),
      params: { guide_day_id: guide_day.id, status: "penalized",
        status_note: "Ausencia informada por operación" }
    assert guide_day.reload.penalized?
    assert_equal "Ausencia informada por operación", guide_day.status_note
    assert AuditLog.exists?(action: "update_sara_availability",
      auditable_id: guide_day.id)

    patch update_sara_availability_work_day_path(@day),
      params: { guide_day_id: other_day.id, status: "day_off" }
    assert_response :not_found
    assert other_day.reload.standby?
  end

  test "HG removal of an assigned priority five guide opens the Sara slot" do
    guide = Guide.create!(name: "Assigned Sara five", priority: 5,
      active: true, pay_category: "freelance_regular",
      skills: [@class_iv, @sara_roll])
    slot = @day.location_slots.create!(location: "Sara-3&4")
    slot.skills << @class_iv
    guide_day = @day.guide_days.create!(guide: guide, status: :standby)
    guide_day.update!(status: :worked, location: "Sara-3&4",
      role_primary: "River Guide")
    @day.update!(status: :generated)

    patch update_sara_availability_work_day_path(@day),
      params: { guide_day_id: guide_day.id, status: "penalized",
        status_note: "Cambio operativo" }

    assert_redirected_to sara_operation_work_day_path(@day)
    assert guide_day.reload.penalized?
    assert_nil guide_day.location
    assert_equal ["Sara-3&4: 0 de 1 puestos cubiertos"],
      @day.roll_coverage_errors
    assignment = CompensationAssignment.find_by!(guide_day: guide_day)
    assert_equal "canceled", assignment.status
  end

  test "HG cannot edit today's availability after the eight PM cutoff" do
    guide = Guide.create!(name: "Sara cutoff five", priority: 5,
      active: true, pay_category: "freelance_regular")
    guide_day = @day.guide_days.create!(guide: guide, status: :standby)
    local_zone = Time.find_zone!("America/Costa_Rica")
    cutoff = local_zone.local(@day.date.year, @day.date.month, @day.date.day, 20, 1)

    travel_to cutoff do
      patch update_sara_availability_work_day_path(@day),
        params: { guide_day_id: guide_day.id, status: "day_off" }
      assert_redirected_to sara_operation_work_day_path(@day)
    end

    assert guide_day.reload.standby?
  end

  test "HG creates and manages priority six without changing priority or economic category" do
    get new_sara_guide_path
    assert_response :success

    assert_difference "Guide.where(priority: 6).count", 1 do
      post sara_guides_path, params: { guide: {
        name: "New Sara reserve", priority: 0, active: true,
        pay_category: "salaried", skill_ids: [@busguide.id]
      } }
    end
    reserve = Guide.find_by!(name: "New Sara reserve")
    assert_redirected_to sara_guides_path
    assert_equal 6, reserve.priority
    assert_not reserve.active?
    assert_equal "freelance_regular", reserve.pay_category
    assert_equal %w[Busguide ClassIV address_Sarapiqui],
      reserve.skills.pluck(:name).sort

    patch sara_guide_path(reserve), params: { guide: {
      name: "Updated Sara reserve", priority: 1,
      skill_ids: []
    } }
    assert_redirected_to sara_guides_path
    assert_equal 6, reserve.reload.priority
    assert_equal "Updated Sara reserve", reserve.name
    assert_equal %w[ClassIV address_Sarapiqui], reserve.skills.pluck(:name).sort

    patch toggle_active_sara_guide_path(reserve)
    assert reserve.reload.active?
    assert @day.guide_days.exists?(guide: reserve)
    patch toggle_active_sara_guide_path(reserve)
    assert_not reserve.reload.active?

    priority_five = Guide.create!(name: "Not a reserve", priority: 5,
      active: false)
    get edit_sara_guide_path(priority_five)
    assert_response :not_found
  end

  test "HG sees freelance label but cannot add extra bus guides" do
    specialist = Guide.create!(name: "Bus specialist for operator", priority: 2,
      active: true, pay_category: "freelance_regular",
      skills: [@class_iv, @busguide])
    Guide.create!(name: "Freelance reserve", priority: 6,
      active: true, pay_category: "freelance_regular",
      skills: [@class_iv, @residence])
    @day.update!(status: :generated)
    slot = @day.location_slots.create!(location: "Sara-3&4")
    slot.skills << @class_iv

    get sara_operation_work_day_path(@day)
    assert_response :success
    assert_select "#day-extra-bus-guides", count: 0
    assert_select "form[action='#{add_sara_bus_guide_work_day_path(@day)}']", count: 0
    assert_select "#day-sara-pending-assignments option", text: /Freelance reserve.*freelance/

    assert_no_difference "@day.location_slots.count" do
      post add_sara_bus_guide_work_day_path(@day),
        params: { location: "Sara-3&4", guide_id: specialist.id }
    end
    assert_redirected_to sara_work_days_path
    assert_nil @day.guide_days.find_by(guide: specialist)
  end

  test "HG fills Sara and adds a PM guide but cannot create a Balsa slot" do
    reserve = Guide.create!(name: "Reserve for manual HG", priority: 6,
      active: false, pay_category: "freelance_regular",
      skills: [@class_iv, @residence])
    @day.update!(status: :generated)
    slot = @day.location_slots.create!(location: "Sara-3&4")
    slot.skills << @class_iv

    assert_not_includes SaraManualAssignment.new(@day)
      .candidates_for(slot).map(&:guide), reserve
    post assign_sara_guide_work_day_path(@day),
      params: { slot_id: slot.id, guide_id: reserve.id }
    assert_nil @day.guide_days.find_by(guide: reserve)

    patch toggle_active_sara_guide_path(reserve)
    assert reserve.reload.active?
    post assign_sara_guide_work_day_path(@day),
      params: { slot_id: slot.id, guide_id: reserve.id }
    assert_redirected_to sara_operation_work_day_path(@day)
    assert @day.guide_days.find_by!(guide: reserve).worked?

    post add_sara_guide_work_day_path(@day),
      params: { location: "PM", guide_id: reserve.id }
    assert_redirected_to sara_operation_work_day_path(@day)
    assert_equal 1, @day.location_slots.count

    other = Guide.create!(name: "Second Sara reserve", priority: 6,
      active: true, pay_category: "freelance_regular",
      skills: [@class_iv, @residence])
    post add_sara_guide_work_day_path(@day),
      params: { location: "PM", guide_id: other.id }
    assert_redirected_to sara_operation_work_day_path(@day)
    assert_equal "PM", @day.guide_days.find_by!(guide: other).location
    assert_equal 2, @day.location_slots.count

    post add_sara_guide_work_day_path(@day),
      params: { location: "Balsa", guide_id: reserve.id }
    assert_equal 2, @day.location_slots.count
  end
end
