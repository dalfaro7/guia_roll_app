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

    # GuideDay exige status_note para assigned_task y penalized.
    if [:assigned_task, :penalized].include?(status.to_sym)
      attributes[:status_note] = "Test status"
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

  test "previous day ranks standby, assigned task, day off, penalized" do
    oscar = Guide.create!(
      name: "Oscar",
      priority: 2,
      active: true,
      fairness_started_on: Date.new(2026, 8, 1)
    )

    maria = Guide.create!(
      name: "Maria",
      priority: 2,
      active: true,
      fairness_started_on: Date.new(2026, 8, 1)
    )

    [@guide_a, @guide_b, oscar, maria].each do |guide|
      (1..3).each do |day|
        create_guide_day(
          guide: guide,
          date: Date.new(2026, 8, day),
          status: :worked
        )
      end
    end

    create_guide_day(guide: @guide_a, date: Date.new(2026, 8, 15), status: :standby)
    create_guide_day(guide: maria, date: Date.new(2026, 8, 15), status: :assigned_task)
    create_guide_day(guide: oscar, date: Date.new(2026, 8, 15), status: :day_off)
    create_guide_day(guide: @guide_b, date: Date.new(2026, 8, 15), status: :penalized)

    ordered = [@guide_b, oscar, maria, @guide_a].sort_by do |guide|
      RollFairnessPolicy.ranking_key_for(guide, before_date: @work_day_date)
    end

    assert_equal [@guide_a, maria, oscar, @guide_b], ordered
  end

  test "mid month entrant starts behind established guide of same priority" do
    @guide_b.update!(fairness_started_on: Date.new(2026, 8, 15))

    (1..3).each do |day|
      create_guide_day(
        guide: @guide_a,
        date: Date.new(2026, 8, day),
        status: :worked
      )
    end

    established_key = RollFairnessPolicy.ranking_key_for(
      @guide_a, before_date: @work_day_date
    )
    entrant_key = RollFairnessPolicy.ranking_key_for(
      @guide_b, before_date: @work_day_date
    )

    assert_ranks_before established_key, entrant_key

    @guide_b.update!(priority: 1)
    higher_priority_key = RollFairnessPolicy.ranking_key_for(
      @guide_b, before_date: @work_day_date
    )
    assert_ranks_before higher_priority_key, established_key
  end

  test "entry balance prevents a jump after first roll work" do
    @guide_b.update!(fairness_started_on: Date.new(2026, 8, 15), fairness_entry_roll_days: 3)

    (1..3).each do |day|
      create_guide_day(
        guide: @guide_a,
        date: Date.new(2026, 8, day),
        status: :worked
      )
    end
    create_guide_day(
      guide: @guide_b,
      date: Date.new(2026, 8, 15),
      status: :worked
    )

    established_key = RollFairnessPolicy.ranking_key_for(
      @guide_a, before_date: @work_day_date
    )
    entrant_key = RollFairnessPolicy.ranking_key_for(
      @guide_b, before_date: @work_day_date
    )

    assert_ranks_before established_key, entrant_key
    snapshot = RollFairnessPolicy.fairness_snapshot_for(
      @guide_b, before_date: @work_day_date
    )
    assert_equal 1, snapshot[:roll_worked_days]
    assert_equal 3, snapshot[:entry_roll_balance]
    assert_equal 4, snapshot[:ranking_roll_days]
  end

  test "entrant stays last across months until first roll assignment" do
    @guide_b.update!(fairness_started_on: Date.new(2026, 8, 15))
    create_guide_day(
      guide: @guide_b,
      date: Date.new(2026, 8, 16),
      status: :assigned_task
    )
    create_guide_day(
      guide: @guide_a,
      date: Date.new(2026, 9, 1),
      status: :worked
    )

    established_key = RollFairnessPolicy.ranking_key_for(
      @guide_a, before_date: Date.new(2026, 9, 5)
    )
    entrant_key = RollFairnessPolicy.ranking_key_for(
      @guide_b, before_date: Date.new(2026, 9, 5)
    )

    assert_ranks_before established_key, entrant_key
  end

  test "activation stores rounded average of other active guides" do
    travel_to Date.new(2026, 9, 19) do
      Guide.where.not(id: [@guide_a.id, @guide_b.id]).update_all(active: false)
      @guide_b.update!(active: false)
      peer = Guide.create!(
        name: "Peer",
        priority: 2,
        active: true,
        fairness_started_on: Date.new(2026, 9, 1)
      )

      create_guide_day(
        guide: @guide_a, date: Date.new(2026, 9, 10), status: :worked
      )
      [11, 12].each do |day|
        create_guide_day(
          guide: peer, date: Date.new(2026, 9, day), status: :worked
        )
      end

      @guide_b.update!(active: true)
      assert_equal Date.new(2026, 9, 19), @guide_b.fairness_started_on
      assert_equal 2, @guide_b.fairness_entry_roll_days

      create_guide_day(
        guide: peer, date: Date.new(2026, 9, 13), status: :worked
      )
      @guide_b.update!(name: "Guide B renamed")
      assert_equal 2, @guide_b.reload.fairness_entry_roll_days

      create_guide_day(
        guide: @guide_b, date: Date.new(2026, 9, 19), status: :worked
      )
      snapshot = RollFairnessPolicy.fairness_snapshot_for(
        @guide_b, before_date: Date.new(2026, 9, 20)
      )
      assert_equal 1, snapshot[:roll_worked_days]
      assert_equal 2, snapshot[:entry_roll_balance]
      assert_equal 3, snapshot[:ranking_roll_days]

      october = RollFairnessPolicy.fairness_snapshot_for(
        @guide_b, before_date: Date.new(2026, 10, 1)
      )
      assert_equal 0, october[:entry_roll_balance]
    end
  end

  test "entry balance remains after a first guide in a later month" do
    @guide_b.update!(
      fairness_started_on: Date.new(2026, 8, 15),
      fairness_entry_roll_days: 2
    )
    create_guide_day(
      guide: @guide_b, date: Date.new(2026, 9, 3), status: :worked
    )

    september = RollFairnessPolicy.fairness_snapshot_for(
      @guide_b, before_date: Date.new(2026, 9, 5)
    )
    assert_equal 1, september[:roll_worked_days]
    assert_equal 2, september[:entry_roll_balance]
    assert_equal 3, september[:ranking_roll_days]

    october = RollFairnessPolicy.fairness_snapshot_for(
      @guide_b, before_date: Date.new(2026, 10, 1)
    )
    assert_equal 0, october[:entry_roll_balance]
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