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

    @guides = Guide.active.order(:name)

    @balances = MonthlyBalance
                  .where(guide: @guides, month: month_date)
                  .includes(:guide)

    balances_by_guide_id = @balances.index_by(&:guide_id)

    @total_worked = @guides.sum do |guide|
      balances_by_guide_id[guide.id]&.worked_days.to_i
    end

    @average =
      if @guides.any?
        @total_worked.to_f / @guides.size
      else
        0
      end

    @dashboard_data = @guides.map do |guide|
      balance = balances_by_guide_id[guide.id]
      worked = balance&.worked_days.to_i

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
        MonthlyBalance
          .where(guide: @selected_guide)
          .order(:month)
          .map do |balance|
            [
              balance.month.strftime("%Y-%m"),
              balance.worked_days.to_i
            ]
          end
      else
        []
      end
  end
end