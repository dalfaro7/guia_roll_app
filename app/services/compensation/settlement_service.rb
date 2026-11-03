module Compensation
  class SettlementService
    ZONE = "America/Costa_Rica"

    def self.week_start(date)
      date - ((date.wday - 3) % 7)
    end

    def self.refresh_for(work_day)
      new(week_start(work_day.date)).refresh!
    end

    def self.close_due!(now: Time.current)
      local_now = now.in_time_zone(ZONE)

      dates = Departure.joins(:work_day)
        .where("work_days.date <= ?", local_now.hour >= 18 ? local_now.to_date : local_now.to_date - 1.day)
        .distinct
        .pluck("work_days.date")
      dates.each do |date|
        new(week_start(date)).refresh!(now: now)
      end

      due_end = local_now.hour >= 18 ? local_now.to_date : local_now.to_date - 1.day
      CompensationSettlement.where(closed_at: nil, paid_at: nil)
        .where("week_end <= ?", due_end)
        .find_each { |settlement| settlement.update!(closed_at: now) }
    end

    def initialize(week_start)
      @week_start = week_start
      @week_end = week_start + 6.days
    end

    def refresh!(now: Time.current)
      assignments = CompensationAssignment.joins(departure: :work_day)
        .where(work_days: { date: @week_start..@week_end })
        .includes(:departure, :guide, :driver, :compensation_lines)
        .to_a

      people = assignments.map { |a| [a.guide_id, a.driver_id] }.uniq
      CompensationSettlement.where(week_start: @week_start)
        .pluck(:guide_id, :driver_id).each { |pair| people << pair }
      people.uniq.each do |guide_id, driver_id|
        next if guide_id.nil? && driver_id.nil?

        person_assignments = assignments.select do |a|
          a.guide_id == guide_id && a.driver_id == driver_id
        end
        refresh_person!(guide_id, driver_id, person_assignments, now)
      end
    end

    private

    def refresh_person!(guide_id, driver_id, assignments, now)
      settlement = CompensationSettlement.find_or_create_by!(
        guide_id: guide_id, driver_id: driver_id, week_start: @week_start
      ) { |record| record.week_end = @week_end }

      settlement.with_lock do
        if settlement.paid?
          create_adjustments_for_paid_week(settlement, assignments)
        else
          local_now = now.in_time_zone(ZONE)
          week_closed = local_now.to_date > @week_end ||
            (local_now.to_date == @week_end && local_now.hour >= 18)
          relevant = assignments.select do |assignment|
            assignment.departure.status != "canceled" &&
              (week_closed ? assignment.status == "performed" :
                %w[planned performed].include?(assignment.status))
          end
          ids = relevant.map(&:id)
          settlement.compensation_settlement_items
            .where.not(compensation_assignment_id: ids).destroy_all

          relevant.each do |assignment|
            item = settlement.compensation_settlement_items.find_or_initialize_by(
              compensation_assignment: assignment
            )
            item.amount_cents = assignment.compensation_lines.sum(&:amount_cents)
            item.details = {
              date: assignment.departure.work_day.date.iso8601,
              departure: assignment.departure.label,
              role_code: assignment.role_code,
              lines: assignment.compensation_lines.map do |line|
                { code: line.code, amount_cents: line.amount_cents,
                  rate_cents: line.rate_cents,
                  discount_percent: line.discount_percent }
              end
            }
            item.save!
          end

          total = settlement.compensation_settlement_items.sum(:amount_cents) +
            settlement.compensation_adjustments.sum(:amount_cents)
          settlement.update!(
            amount_cents: total,
            closed_at: week_closed ? (settlement.closed_at || now) : nil
          )
        end
      end
    end

    def create_adjustments_for_paid_week(settlement, assignments)
      originals = settlement.compensation_settlement_items
        .index_by(&:compensation_assignment_id)
      (assignments.map(&:id) | originals.keys).each do |assignment_id|
        assignment = assignments.find { |a| a.id == assignment_id }
        actual = if assignment&.status == "performed" &&
            assignment.departure.status != "canceled"
          assignment.compensation_lines.sum(&:amount_cents)
        else
          0
        end
        difference = actual - (originals[assignment_id]&.amount_cents || 0)
        prior = CompensationAdjustment.joins(:compensation_settlement)
          .where(source_assignment_id: assignment_id,
            compensation_settlements: {
              guide_id: settlement.guide_id,
              driver_id: settlement.driver_id
            })
          .where("compensation_settlements.week_start > ?", settlement.week_start)
          .includes(:compensation_settlement)
          .to_a
        paid_amount = prior.select { |item| item.compensation_settlement.paid? }
          .sum(&:amount_cents)
        pending = prior.reject { |item| item.compensation_settlement.paid? }
        pending_amount = difference - paid_amount

        if pending_amount.zero?
          pending.each do |item|
            target = item.compensation_settlement
            item.destroy!
            recalculate_total!(target)
          end
          next
        end

        target = next_unpaid_settlement_for(settlement)
        if pending.one? && pending.first.compensation_settlement_id == target.id &&
            pending.first.amount_cents == pending_amount
          next
        end

        raise "La corrección de un período pagado necesita responsable y motivo" if
          Compensation::Current.actor.blank? || Compensation::Current.reason.blank?

        pending.reject { |item| item.compensation_settlement_id == target.id }
          .each do |item|
            old_target = item.compensation_settlement
            item.destroy!
            recalculate_total!(old_target)
          end
        adjustment = target.compensation_adjustments.find_or_initialize_by(
          source_assignment_id: assignment_id
        )
        adjustment.amount_cents = pending_amount
        adjustment.reason = Compensation::Current.reason
        adjustment.created_by = Compensation::Current.actor
        adjustment.save!
        recalculate_total!(target)
      end
    end

    def recalculate_total!(settlement)
      settlement.update!(amount_cents:
        settlement.compensation_settlement_items.sum(:amount_cents) +
        settlement.compensation_adjustments.sum(:amount_cents))
    end

    def next_unpaid_settlement_for(source)
      next_start = source.week_start + 7.days
      loop do
        target = CompensationSettlement.find_or_create_by!(
          guide_id: source.guide_id, driver_id: source.driver_id,
          week_start: next_start
        ) { |record| record.week_end = next_start + 6.days }
        return target unless target.paid?

        next_start += 7.days
      end
    end
  end
end
