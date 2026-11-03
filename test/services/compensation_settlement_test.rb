require "test_helper"
require_relative "../../db/migrate/20261103000000_create_compensation_system"

class CompensationSettlementTest < ActiveSupport::TestCase
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
    @zone = Time.find_zone!("America/Costa_Rica")
    @date = Date.current + ((2 - Date.current.wday) % 7) + 7.days
    @guide = Guide.create!(name: "Settlement guide", priority: 3,
      active: true, pay_category: "freelance_regular")
    @day = WorkDay.create!(date: @date, guides_requested: 0)
    @departure = @day.departures.create!(label: "Balsa", location: "Balsa",
      starts_at: @zone.local(@date.year, @date.month, @date.day, 6))
    @assignment = @departure.compensation_assignments.create!(
      guide: @guide, role_code: "river_guide")
    Compensation::RepriceDay.call(@day)
  end

  test "day closes at 18:00 and corrections to a paid week settle once" do
    travel_to @zone.local(@date.year, @date.month, @date.day, 18, 1) do
      CompensationCloseDueDaysJob.perform_now
      assert_equal "performed", @assignment.reload.status
      assert_equal "completed", @departure.reload.status

      settlement = CompensationSettlement.find_by!(guide: @guide,
        week_start: @date - 6.days)
      assert_equal 5_000, settlement.amount_cents
      assert settlement.closed_at.present?
      paid_item = settlement.compensation_settlement_items.first
      assert_equal "river_guide", paid_item.details.fetch("role_code")
      assert_equal 5_000, paid_item.details.fetch("lines").first.fetch("amount_cents")

      admin = User.create!(name: "Accounting admin", email: "accounting-test@example.com",
        password: "password123", role: :admin)
      settlement.mark_paid!(admin)

      Compensation::Current.set(actor: admin, reason: "Corrección comprobada") do
        @assignment.update!(status: "canceled")
        Compensation::RepriceDay.call(@day)
      end
      next_week = CompensationSettlement.find_by!(guide: @guide,
        week_start: @date + 1.day)
      assert_equal(-5_000, next_week.reload.amount_cents)
      assert_equal 5_000, settlement.reload.amount_cents
      assert_equal 5_000,
        paid_item.reload.details.fetch("lines").first.fetch("amount_cents")
      CompensationCloseDueDaysJob.perform_now
      assert_equal(-5_000, next_week.reload.amount_cents)
      next_tuesday = @date + 7.days
      Compensation::SettlementService.close_due!(now: @zone.local(
        next_tuesday.year, next_tuesday.month, next_tuesday.day, 18, 1
      ))
      assert next_week.reload.closed_at.present?

      Compensation::Current.set(actor: admin, reason: "Restitución comprobada") do
        @assignment.update!(status: "performed")
        Compensation::RepriceDay.call(@day)
      end
      assert_equal 0, next_week.reload.amount_cents
      assert_empty next_week.compensation_adjustments.reload
    end
  end
end
