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

  %w[draft generated published].each do |state|
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
