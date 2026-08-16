require "test_helper"

class RollFairnessPolicyTest < ActiveSupport::TestCase

  setup do
    @work_day_date = Date.new(2026, 8, 16)

    @guide_a = Guide.create!(
      name: "Guide A",
      priority: 2,
      active: true,
      fairness_started_on: Date.new(2026, 8, 1)
    )

    @guide_b = Guide.create!(
      name: "Guide B",
      priority: 2,
      active: true,
      fairness_started_on: Date.new(2026, 8, 1)
    )
  end

  # ----------------------------------------------------------
  # Helper para crear GuideDay históricos.
  #
  # WorkDay tiene una validación que impide crear fechas
  # pasadas normalmente. Para estos tests necesitamos
  # reconstruir historial, por eso el WorkDay se guarda
  # sin validaciones.
  # ----------------------------------------------------------
  def create_guide_day(guide:, date:, status:)
    work_day = WorkDay.find_or_initialize_by(date: date)

    if work_day.new_record?
      work_day.status = :draft
      work_day.guides_requested = 0
      work_day.save!(validate: false)
    end

    guide_day =
      work_day.guide_days.find_or_initialize_by(
        guide: guide
      )

    attributes = {
      status: status
    }

    # GuideDay exige status_note cuando es assigned_task.
    if status.to_sym == :assigned_task
      attributes[:status_note] = "Test assigned task"
    end

    guide_day.update!(attributes)

    guide_day
  end

  # ----------------------------------------------------------
  # Helper para comparar ranking keys.
  #
  # ranking_key_for devuelve Array.
  # Array implementa <=> pero no < directamente.
  # ----------------------------------------------------------
  def assert_ranks_before(first_key, second_key)
    assert_operator(
      first_key <=> second_key,
      :<,
      0
    )
  end

  test "guide with fewer roll worked days ranks first" do
    create_guide_day(
      guide: @guide_a,
      date: Date.new(2026, 8, 10),
      status: :worked
    )

    create_guide_day(
      guide: @guide_a,
      date: Date.new(2026, 8, 11),
      status: :worked
    )

    create_guide_day(
      guide: @guide_b,
      date: Date.new(2026, 8, 10),
      status: :worked
    )

    key_a =
      RollFairnessPolicy.ranking_key_for(
        @guide_a,
        before_date: @work_day_date
      )

    key_b =
      RollFairnessPolicy.ranking_key_for(
        @guide_b,
        before_date: @work_day_date
      )

    assert_ranks_before key_b, key_a
  end

  test "guide with lower priority number ranks first" do
    @guide_a.update!(
      priority: 1
    )

    @guide_b.update!(
      priority: 2
    )

    key_a =
      RollFairnessPolicy.ranking_key_for(
        @guide_a,
        before_date: @work_day_date
      )

    key_b =
      RollFairnessPolicy.ranking_key_for(
        @guide_b,
        before_date: @work_day_date
      )

    assert_ranks_before key_a, key_b
  end

  test "consecutive roll work breaks tie against guide who worked yesterday" do
    create_guide_day(
      guide: @guide_a,
      date: Date.new(2026, 8, 15),
      status: :worked
    )

    create_guide_day(
      guide: @guide_b,
      date: Date.new(2026, 8, 10),
      status: :worked
    )

    snapshot_a =
      RollFairnessPolicy.fairness_snapshot_for(
        @guide_a,
        before_date: @work_day_date
      )

    snapshot_b =
      RollFairnessPolicy.fairness_snapshot_for(
        @guide_b,
        before_date: @work_day_date
      )

    assert_equal 1,
                 snapshot_a[:roll_worked_days]

    assert_equal 1,
                 snapshot_b[:roll_worked_days]

    assert_equal 1,
                 snapshot_a[:consecutive_roll_days]

    assert_equal 0,
                 snapshot_b[:consecutive_roll_days]

    key_a =
      RollFairnessPolicy.ranking_key_for(
        @guide_a,
        before_date: @work_day_date
      )

    key_b =
      RollFairnessPolicy.ranking_key_for(
        @guide_b,
        before_date: @work_day_date
      )

    assert_ranks_before key_b, key_a
  end

  test "assigned task does not consume roll fairness when flag is false" do
    create_guide_day(
      guide: @guide_a,
      date: Date.new(2026, 8, 15),
      status: :assigned_task
    )

    snapshot =
      RollFairnessPolicy.fairness_snapshot_for(
        @guide_a,
        before_date: @work_day_date
      )

    assert_equal false,
                 RollFairnessPolicy.assigned_task_counts_as_roll_work?

    assert_equal 0,
                 snapshot[:roll_worked_days]

    assert_equal 0,
                 snapshot[:consecutive_roll_days]

    assert_equal Date.new(2026, 8, 1),
                 snapshot[:waiting_since]
  end

  test "assigned task counts as service even when it does not consume fairness" do
    assert_includes(
      RollFairnessPolicy.service_statuses,
      :assigned_task
    )

    refute_includes(
      RollFairnessPolicy.fairness_statuses,
      :assigned_task
    )
  end

  test "fairness ignores worked days before fairness started on" do
    @guide_a.update!(
      fairness_started_on: Date.new(2026, 8, 10)
    )

    create_guide_day(
      guide: @guide_a,
      date: Date.new(2026, 8, 5),
      status: :worked
    )

    create_guide_day(
      guide: @guide_a,
      date: Date.new(2026, 8, 12),
      status: :worked
    )

    snapshot =
      RollFairnessPolicy.fairness_snapshot_for(
        @guide_a,
        before_date: @work_day_date
      )

    assert_equal 1,
                 snapshot[:roll_worked_days]

    assert_equal Date.new(2026, 8, 10),
                 snapshot[:fairness_started_on]
  end

  test "newly activated guide does not receive artificial waiting advantage" do
    @guide_a.update!(
      fairness_started_on: Date.new(2026, 8, 1)
    )

    @guide_b.update!(
      fairness_started_on: Date.new(2026, 8, 15)
    )

    create_guide_day(
      guide: @guide_a,
      date: Date.new(2026, 8, 14),
      status: :worked
    )

    snapshot_a =
      RollFairnessPolicy.fairness_snapshot_for(
        @guide_a,
        before_date: @work_day_date
      )

    snapshot_b =
      RollFairnessPolicy.fairness_snapshot_for(
        @guide_b,
        before_date: @work_day_date
      )

    assert_equal Date.new(2026, 8, 14),
                 snapshot_a[:waiting_since]

    assert_equal Date.new(2026, 8, 15),
                 snapshot_b[:waiting_since]
  end

  test "waiting since favors guide who has waited longer when other criteria tie" do
    create_guide_day(
      guide: @guide_a,
      date: Date.new(2026, 8, 14),
      status: :worked
    )

    create_guide_day(
      guide: @guide_b,
      date: Date.new(2026, 8, 12),
      status: :worked
    )

    snapshot_a =
      RollFairnessPolicy.fairness_snapshot_for(
        @guide_a,
        before_date: @work_day_date
      )

    snapshot_b =
      RollFairnessPolicy.fairness_snapshot_for(
        @guide_b,
        before_date: @work_day_date
      )

    assert_equal 1,
                 snapshot_a[:roll_worked_days]

    assert_equal 1,
                 snapshot_b[:roll_worked_days]

    assert_equal 0,
                 snapshot_a[:consecutive_roll_days]

    assert_equal 0,
                 snapshot_b[:consecutive_roll_days]

    assert_equal Date.new(2026, 8, 14),
                 snapshot_a[:waiting_since]

    assert_equal Date.new(2026, 8, 12),
                 snapshot_b[:waiting_since]

    key_a =
      RollFairnessPolicy.ranking_key_for(
        @guide_a,
        before_date: @work_day_date
      )

    key_b =
      RollFairnessPolicy.ranking_key_for(
        @guide_b,
        before_date: @work_day_date
      )

    assert_ranks_before key_b, key_a
  end

  test "current work day is not included in fairness calculation" do
    create_guide_day(
      guide: @guide_a,
      date: @work_day_date,
      status: :worked
    )

    snapshot =
      RollFairnessPolicy.fairness_snapshot_for(
        @guide_a,
        before_date: @work_day_date
      )

    assert_equal 0,
                 snapshot[:roll_worked_days]
  end

  test "technical id is final deterministic tie breaker" do
    key_a =
      RollFairnessPolicy.ranking_key_for(
        @guide_a,
        before_date: @work_day_date
      )

    key_b =
      RollFairnessPolicy.ranking_key_for(
        @guide_b,
        before_date: @work_day_date
      )

    if @guide_a.id < @guide_b.id
      assert_ranks_before key_a, key_b
    else
      assert_ranks_before key_b, key_a
    end
  end
end