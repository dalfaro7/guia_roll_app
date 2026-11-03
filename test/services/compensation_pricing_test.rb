require "test_helper"
require_relative "../../db/migrate/20261103000000_create_compensation_system"

class CompensationPricingTest < ActiveSupport::TestCase
  setup do
    if CompensationRate.none?
      CompensationRate.insert_all!(
        CreateCompensationSystem::INITIAL_RATES.map do |code, cents|
          { code: code.to_s, amount_cents: cents,
            effective_at: Time.utc(2020, 1, 1),
            created_at: Time.current, updated_at: Time.current }
        end
      )
    end
    @date = Date.current + 2.days
    @work_day = WorkDay.create!(date: @date, guides_requested: 0)
    @zone = Time.find_zone!("America/Costa_Rica")
    @first = @work_day.departures.create!(
      label: "Balsa", location: "Balsa",
      starts_at: @zone.local(@date.year, @date.month, @date.day, 6)
    )
  end

  def guide(name, category: "freelance_regular", level_two: false)
    Guide.create!(name: name, priority: 3, active: true,
      pay_category: category, pay_level_two: level_two)
  end

  def assignment(departure, person, role, **extra)
    attributes = { departure: departure, role_code: role }.merge(extra)
    attributes[person.is_a?(Guide) ? :guide : :driver] = person
    record = CompensationAssignment.create!(attributes)
    Compensation::RepriceDay.call(@work_day)
    record.reload
  end

  test "regular guide receives one base and both compatible bonuses" do
    record = assignment(@first, guide("Regular"), "river_guide",
      also_drives: true, photo_task: "take_and_send")

    assert_equal 8_400, record.total_cents
    assert_equal %w[bonus_guide_drives bonus_photo_take_and_send guide_regular],
      record.compensation_lines.pluck(:code).sort
  end

  test "only the main function is discounted on a second departure" do
    person = guide("Two departures")
    assignment(@first, person, "river_guide")
    second = @work_day.departures.create!(
      label: "Sara clase 3", location: "Sara-3",
      starts_at: @zone.local(@date.year, @date.month, @date.day, 10)
    )
    record = assignment(second, person, "river_guide", also_drives: true)

    assert_equal 4_900, record.total_cents
    assert_equal 30, record.compensation_lines.find_by!(code: "guide_regular").discount_percent
    assert_equal 1_400, record.compensation_lines.find_by!(code: "bonus_guide_drives").amount_cents

    third = @work_day.departures.create!(
      label: "PM", location: "PM",
      starts_at: @zone.local(@date.year, @date.month, @date.day, 14)
    )
    assert_raises(ActiveRecord::RecordInvalid) do
      assignment(third, person, "river_guide")
    end
  end

  test "two photographers each receive the photo extra but only one is principal" do
    first = assignment(@first, guide("Photo one"), "photographer",
      principal_photographer: true)
    second = assignment(@first, guide("Photo two"), "photographer")

    assert_equal 7_000, first.total_cents
    assert_equal 7_000, second.total_cents
    assert_raises(ActiveRecord::RecordInvalid) do
      first.update!(principal_photographer: false)
    end
    assert_raises(ActiveRecord::RecordInvalid) do
      assignment(@first, guide("Sender"), "river_guide", photo_task: "send_only")
    end
  end

  test "one departure cannot pay two separate photo senders" do
    assignment(@first, guide("First sender"), "river_guide",
      photo_task: "take_and_send")
    error = assert_raises(ActiveRecord::RecordInvalid) do
      assignment(@first, guide("Second sender"), "river_guide",
        photo_task: "send_only")
    end
    assert_includes error.record.errors.full_messages.join(" "),
      "Ya existe un responsable de fotos"
  end

  test "salaried bus guide with photos receives only the photo bonus" do
    record = assignment(@first, guide("Salary", category: "salaried", level_two: true),
      "river_guide", bus_guide: true, photo_task: "take_and_send")

    assert_equal 2_000, record.total_cents
    assert_equal ["bonus_photo_take_and_send"], record.compensation_lines.pluck(:code)
  end

  test "freelance head guide replaces base and salaried head guide has no additional fee" do
    freelance = assignment(@first, guide("Freelance HG"), "hg_balsa")
    salary = assignment(@first, guide("Salary HG", category: "salaried"), "hg_balsa")

    assert_equal 9_000, freelance.total_cents
    assert_equal 0, salary.total_cents
    assert_raises(ActiveRecord::RecordInvalid) do
      assignment(@first, guide("Invalid HG"), "hg_balsa", also_drives: true)
    end
  end

  test "second driver departure discounts only its main rate" do
    driver = Driver.create!(name: "Driver A")
    assignment(@first, driver, "driver_la_fortuna")
    second = @work_day.departures.create!(
      label: "Sara clase 4", location: "Sara-4",
      starts_at: @zone.local(@date.year, @date.month, @date.day, 10)
    )

    assert_equal 2_800,
      assignment(second, driver, "driver_la_fortuna").total_cents
  end

  test "Host is an assigned task and does not discount a later guided outing" do
    person = guide("Host then guide")
    assert_equal 2_000, assignment(@first, person, "host").total_cents
    second = @work_day.departures.create!(
      label: "Sara clase 3", location: "Sara-3",
      starts_at: @zone.local(@date.year, @date.month, @date.day, 10)
    )
    guided = assignment(second, person, "river_guide")
    assert_equal 5_000, guided.total_cents
    assert_equal 0, guided.compensation_lines.find_by!(code: "guide_regular").discount_percent
  end

  test "future rates reprice before departure and the amount freezes at start" do
    person = guide("Rate snapshot")
    record = assignment(@first, person, "river_guide")
    assert_equal 5_000, record.total_cents

    CompensationRate.create!(code: "guide_regular", amount_cents: 5_500,
      effective_at: Time.current + 1.day)
    assert_equal 5_500, record.reload.total_cents

    travel_to @first.starts_at + 1.minute do
      person.update!(pay_category: "freelance_invoice")
      Compensation::RepriceDay.call(@work_day)
      assert_equal 5_500, record.reload.total_cents
      assert_equal "freelance_regular", record.pay_category_snapshot
    end
  end

  test "a missing guide profile can be completed after the departure" do
    person = guide("Missing profile", category: nil)
    record = assignment(@first, person, "river_guide")
    assert record.pricing_error.present?

    travel_to @first.starts_at + 1.minute do
      person.update!(pay_category: "freelance_regular")
      assert_equal 5_000, record.reload.total_cents
      assert_nil record.pricing_error
    end
  end

  test "generated guide day creates a priced assignment without changing fairness priority" do
    person = guide("Generated", category: "freelance_apprentice")
    guide_day = @work_day.guide_days.create!(guide: person, status: "standby")
    guide_day.update!(status: "worked", role_primary: "River Guide", location: "Balsa")

    record = CompensationAssignment.find_by!(guide_day: guide_day)
    assert_equal 4_000, record.total_cents
    assert_equal 3, person.reload.priority

    second = @work_day.departures.create!(
      label: "Sara clase 4", location: "Sara-4",
      starts_at: @zone.local(@date.year, @date.month, @date.day, 10)
    )
    assignment(second, person, "river_guide")
    assert_equal 2, RollFairnessPolicy.roll_worked_days_for_guide(
      person, before_date: @date + 1.day
    )
    snapshot = RollFairnessPolicy.fairness_snapshot_for(
      person, before_date: @date + 1.day
    )
    assert_equal @date, snapshot[:waiting_since]
    assert_equal 1, snapshot[:consecutive_roll_days]
    assert_equal 0, RollFairnessPolicy.ranking_key_for(
      person, before_date: @date + 1.day
    )[1]

    guide_day.update!(status: "standby")
    assert_equal "canceled", record.reload.status
    assert_equal 0, record.total_cents
    guide_day.update!(status: "worked")
    assert_equal "planned", record.reload.status
    assert_equal 4_000, record.total_cents
  end

  test "future published guide days are backfilled after activation" do
    person = guide("Already scheduled")
    guide_day = @work_day.guide_days.create!(guide: person, status: "standby")
    guide_day.update_columns(status: GuideDay.statuses.fetch("worked"),
      role_primary: "River Guide", location: "Balsa")
    assert_nil CompensationAssignment.find_by(guide_day: guide_day)

    Compensation::ScheduleSync.backfill_future!

    record = CompensationAssignment.find_by!(guide_day: guide_day)
    assert_equal 5_000, record.total_cents
  end

  test "manual assignment does not double count an existing worked guide day" do
    person = guide("Manual replacement")
    guide_day = @work_day.guide_days.create!(guide: person, status: "standby")
    guide_day.update_columns(status: GuideDay.statuses.fetch("worked"),
      role_primary: "River Guide", location: "Balsa")
    assignment(@first, person, "river_guide")

    assert_equal 1, RollFairnessPolicy.roll_worked_days_for_guide(
      person, before_date: @date + 1.day
    )
  end

  test "removing a guide from logistics cancels its linked manual valuation" do
    person = guide("Removed guide")
    guide_day = @work_day.guide_days.create!(guide: person, status: "standby")
    guide_day.update!(status: "worked", role_primary: "River Guide",
      location: "Balsa")
    record = CompensationAssignment.find_by!(guide_day: guide_day)
    record.update!(source: "manual")

    guide_day.update!(status: "standby")

    assert_equal "canceled", record.reload.status
    assert_equal 0, record.total_cents
  end

  test "two guide outings consume two fairness opportunities while host consumes none" do
    person = guide("Fairness outings")
    assignment(@first, person, "river_guide")
    second = @work_day.departures.create!(
      label: "Sara clase 3", location: "Sara-3",
      starts_at: @zone.local(@date.year, @date.month, @date.day, 10)
    )
    assignment(second, person, "river_guide")

    assert_equal 2, RollFairnessPolicy.roll_worked_days_for_guide(
      person, before_date: @date + 1.day
    )

    host = guide("Host fairness")
    assignment(@first, host, "host")
    assert_equal 0, RollFairnessPolicy.roll_worked_days_for_guide(
      host, before_date: @date + 1.day
    )
  end
end
