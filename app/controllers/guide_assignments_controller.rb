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
    return unless @guide

    range = @week_start..@report_end
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
        day_assignments.select { |assignment| assignment.status == "performed" }
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
