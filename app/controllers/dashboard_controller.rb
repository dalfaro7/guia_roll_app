class DashboardController < ApplicationController
  def index
    if params[:month].present?
      begin
        year, month = params[:month].split("-").map(&:to_i)
        @month = Date.new(year, month, 1)
      rescue
        @month = Date.today.beginning_of_month
      end
    else
      @month = Date.today.beginning_of_month
    end

    month_range = @month.beginning_of_month..@month.end_of_month

    @guides = Guide.active.order(:name)

    worked_days_by_guide_id = GuideDay
      .joins(:work_day)
      .where(guide: @guides, status: :worked)
      .where(work_days: { date: month_range })
      .group(:guide_id)
      .count

    @total_worked = @guides.sum do |guide|
      worked_days_by_guide_id[guide.id].to_i
    end

    @average =
      if @guides.any?
        @total_worked.to_f / @guides.size
      else
        0
      end

    @dashboard_data = @guides.map do |guide|
      worked = worked_days_by_guide_id[guide.id].to_i

      percentage =
        @total_worked > 0 ? (worked.to_f / @total_worked * 100).round(2) : 0

      deviation = (worked - @average).round(2)

      {
        guide: guide,
        worked: worked,
        percentage: percentage,
        deviation: deviation
      }
    end.sort_by { |data| [-data[:worked], data[:guide].name] }

    @chart_data = @dashboard_data.map do |data|
      [data[:guide].name, data[:worked]]
    end

    @selected_guide =
      if params[:guide_id].present?
        @guides.find { |g| g.id == params[:guide_id].to_i } || @guides.first
      else
        @guides.first
      end

    @historical_data =
  if @selected_guide.present?
    GuideDay
      .joins(:work_day)
      .where(guide: @selected_guide, status: :worked)
      .group(Arel.sql("DATE_TRUNC('month', work_days.date)"))
      .order(Arel.sql("DATE_TRUNC('month', work_days.date)"))
      .count
      .map do |month_date, worked_days|
        [
          month_date.strftime("%Y-%m"),
          worked_days.to_i
        ]
      end
  else
    []
  end
  end
end