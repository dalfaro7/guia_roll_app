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

    month_date = @month.beginning_of_month

    @balances = MonthlyBalance
                  .includes(:guide)
                  .where(month: month_date)

    @total_worked = @balances.sum(:worked_days)
    @average = @balances.average(:worked_days).to_f

    @dashboard_data = @balances.map do |balance|
      worked = balance.worked_days
      percentage = @total_worked > 0 ? (worked.to_f / @total_worked * 100).round(2) : 0
      deviation = (worked - @average).round(2)

      {
        guide: balance.guide,
        worked: worked,
        percentage: percentage,
        deviation: deviation
      }
    end.sort_by { |d| -d[:worked] }

    @chart_data = @dashboard_data.map do |data|
      [data[:guide].name, data[:worked]]
    end

    @guides = Guide.active.order(:name)

    @selected_guide =
      if params[:guide_id].present?
        Guide.find(params[:guide_id])
      else
        @guides.first
      end

    # HISTORICAL DATA CORRECTA (solo del guía seleccionado)
    published_days = WorkDay
      .where(status: "published", guide_id: @selected_guide.id)

   @historical_data = MonthlyBalance
  .where(guide: @selected_guide)
  .order(:month)
  .map do |balance|
    [
      balance.month.strftime("%Y-%m"),  # formato ISO simple
      balance.worked_days.to_i
    ]
  end

    Rails.logger.info "HISTORICAL DATA:"
    Rails.logger.info @historical_data.inspect
    Rails.logger.info @historical_data.class
    Rails.logger.info @historical_data.first.first.class if @historical_data.any?
  end
end