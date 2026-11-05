class GuideAssignmentsController < ApplicationController
  before_action :require_compensation_view!

  def index
    @guides = Guide.order(:name).to_a
    @guide = params[:guide_id].present? ? Guide.find(params[:guide_id]) : @guides.first

    local_now = Time.current.in_time_zone("America/Costa_Rica")
    @today = local_now.to_date
    @current_week_start = Compensation::SettlementService.week_start(@today)
    @latest_closed_week_start = if @today.tuesday? &&
        Compensation::EditWindow.cutoff_reached?(now: local_now)
      @current_week_start
    else
      @current_week_start - 7.days
    end
    selected_date = params[:week].present? ? Date.iso8601(params[:week]) : @latest_closed_week_start
    @week_start = Compensation::SettlementService.week_start(selected_date)
    raise Date::Error, "La fecha es futura" if selected_date > @today

    @week_end = @week_start + 6.days
    @week_open = @week_start > @latest_closed_week_start
    @report_end = [@week_end, @today].min
    range = @week_start..@report_end
    load_operation_expenses(range)
    return unless @guide

    guide_days = GuideDay.joins(:work_day)
      .where(guide: @guide, work_days: { date: range })
      .includes(:work_day).index_by { |guide_day| guide_day.work_day.date }
    assignments = CompensationAssignment.joins(departure: :work_day)
      .where(guide: @guide, work_days: { date: range })
      .includes(:compensation_lines, departure: :work_day)
      .order("departures.starts_at ASC, compensation_assignments.id ASC")
      .group_by { |assignment| assignment.departure.work_day.date }

    @settlement = CompensationSettlement.find_by(guide: @guide, week_start: @week_start)
    items = @settlement&.compensation_settlement_items&.includes(:compensation_assignment)&.to_a || []
    items_by_day = items.group_by { |item| Date.iso8601(item.details.fetch("date")) }
    @adjustments = if @settlement
      @settlement.compensation_adjustments
        .includes(source_assignment: { departure: :work_day }).to_a
    else
      []
    end
    @days = range.map do |date|
      day_assignments = assignments.fetch(date, [])
      day_items = items_by_day.fetch(date, [])
      total_cents = if @settlement
        day_items.sum(&:amount_cents)
      else
        day_assignments.select { |assignment|
          assignment.status == "performed" ||
            (@week_open && date == @today && assignment.status == "planned")
        }
          .sum(&:total_cents)
      end
      { date: date, guide_day: guide_days[date], assignments: day_assignments,
        items: day_items, items_by_assignment: day_items.index_by(&:compensation_assignment_id),
        total_cents: total_cents }
    end
    @weekly_total_cents = if @week_open
      @days.sum { |day| day[:total_cents] } + @adjustments.sum(&:amount_cents)
    else
      @settlement&.amount_cents || @days.sum { |day| day[:total_cents] }
    end
    load_earnings_chart
  rescue Date::Error, ActiveRecord::RecordNotFound
    redirect_to guide_assignments_path, alert: "Guía o semana inválida. Consulte una fecha hasta hoy."
  end

  private

  def load_operation_expenses(range)
    totals = range.index_with { { guide_cents: 0, driver_cents: 0,
      transport_cents: 0 } }
    @operation_payment_details = []
    settlements = CompensationSettlement.where(week_start: @week_start)
      .includes(:driver, :compensation_settlement_items,
        :compensation_adjustments).to_a
    snapshot_assignment_ids = []

    unless @week_open
      settlements.select { |settlement| settlement.closed_at.present? }.each do |settlement|
        key = settlement.guide_id.present? ? :guide_cents : :driver_cents
        settlement.compensation_settlement_items.each do |item|
          date = Date.iso8601(item.details.fetch("date"))
          next unless totals.key?(date)

          totals[date][key] += item.amount_cents
          snapshot_assignment_ids << item.compensation_assignment_id
          if settlement.driver_id.present?
            @operation_payment_details << { date: date, kind: "Chofer",
              recipient_id: settlement.driver_id, recipient: settlement.driver.name,
              concept: item.details.fetch("departure", "Salida"),
              amount_cents: item.amount_cents }
          end
        end
      end
    end

    CompensationAssignment.joins(departure: :work_day)
      .where(status: %w[performed planned], work_days: { date: range })
      .where.not(departures: { status: "canceled" })
      .includes(:driver, :compensation_lines, departure: :work_day).each do |assignment|
        next if snapshot_assignment_ids.include?(assignment.id)

        date = assignment.departure.work_day.date
        next if assignment.status == "planned" && !(@week_open && date == @today)

        key = assignment.guide_id.present? ? :guide_cents : :driver_cents
        amount_cents = assignment.compensation_lines.sum(&:amount_cents)
        totals[date][key] += amount_cents
        if assignment.driver_id.present?
          @operation_payment_details << { date: date, kind: "Chofer",
            recipient_id: assignment.driver_id, recipient: assignment.driver.name,
            concept: assignment.departure.label,
            amount_cents: amount_cents }
        end
      end

    BusAssignment.joins(:work_day)
      .where(work_days: { date: range }).includes(:work_day, :bus, :driver).each do |assignment|
        date = assignment.work_day.date
        totals[date][:transport_cents] += assignment.cost_cents
        next if assignment.internal_fleet_snapshot?

        @operation_payment_details << { date: date, kind: "Empresa",
          recipient_id: assignment.transport_company_snapshot_id,
          recipient: assignment.transport_company_name_snapshot,
          concept: [assignment.location, assignment.bus.alias,
            ("Chofer: #{assignment.driver.name}" if assignment.driver)].compact.join(" · "),
          amount_cents: assignment.cost_cents }
      end

    @driver_adjustments_cents = 0
    settlements.select { |settlement| settlement.driver_id.present? }.each do |settlement|
      settlement.compensation_adjustments.each do |adjustment|
        @driver_adjustments_cents += adjustment.amount_cents
        @operation_payment_details << { date: nil, kind: "Chofer",
          recipient_id: settlement.driver_id, recipient: settlement.driver.name,
          concept: "Ajuste de período anterior: #{adjustment.reason}",
          amount_cents: adjustment.amount_cents }
      end
    end
    @operation_payment_details.sort_by! do |detail|
      [detail[:date] || @week_end + 1.day, detail[:kind], detail[:recipient]]
    end
    @payment_totals_by_recipient = @operation_payment_details
      .group_by { |detail| [detail[:kind], detail[:recipient_id]] }
      .map do |(kind, _id), details|
        { kind: kind, recipient: details.first[:recipient],
          amount_cents: details.sum { |detail| detail[:amount_cents] } }
      end.sort_by { |row| [row[:kind], row[:recipient]] }

    @operation_days = totals.map do |date, amounts|
      amounts.merge(date: date, total_cents: amounts[:guide_cents] +
        amounts[:driver_cents] + amounts[:transport_cents])
    end
    @operation_adjustments_cents = settlements.sum do |settlement|
      settlement.compensation_adjustments.sum(&:amount_cents)
    end
    @operation_weekly_total_cents = @operation_days.sum { |day| day[:total_cents] } +
      @operation_adjustments_cents
    @driver_weekly_total_cents = @operation_days.sum { |day| day[:driver_cents] } +
      @driver_adjustments_cents
    @company_weekly_total_cents = @operation_days.sum { |day| day[:transport_cents] }
  end

  def load_earnings_chart
    @month_range = @report_end.beginning_of_month..@report_end.end_of_month
    @fortnight_range = if @report_end.day <= 15
      @report_end.beginning_of_month..@report_end.change(day: 15)
    else
      @report_end.change(day: 16)..@report_end.end_of_month
    end
    chart_end = @week_open ? @report_end : @month_range.last
    earnings = CompensationAssignment.joins(departure: :work_day)
      .where(guide: @guide, status: "performed",
        work_days: { date: @month_range.first..chart_end }, departures: { status: "completed" })
      .includes(:compensation_lines, departure: :work_day)
    @month_total_cents = earnings.sum(&:total_cents)
    @fortnight_total_cents = earnings.select do |assignment|
      @fortnight_range.cover?(assignment.departure.work_day.date)
    end.sum(&:total_cents)
    @chart_max_cents = [@month_total_cents, @fortnight_total_cents, 1].max
  end
end
