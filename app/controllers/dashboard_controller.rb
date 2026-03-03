class DashboardController < ApplicationController
  def index
    # =====================================
    # 1️⃣ Determinar mes seleccionado
    # =====================================

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

    # =====================================
    # 2️⃣ Cargar guías activos
    # =====================================

    @guides = Guide.active.order(:name)

    # =====================================
    # 3️⃣ Garantizar balances del mes
    # =====================================

    @balances = MonthlyBalance
              .where(guide: @guides, month: month_date)
              .includes(:guide)

    # =====================================
    # 4️⃣ Métricas generales (blindadas contra nil)
    # =====================================

    @total_worked = @balances.sum { |b| b.worked_days.to_i }

    @average =
      if @balances.any?
        @balances.sum { |b| b.worked_days.to_i }.to_f / @balances.size
      else
        0
      end

    # =====================================
    # 5️⃣ Datos principales del dashboard
    # =====================================

    @dashboard_data = @balances.map do |balance|
      worked = balance.worked_days.to_i
      percentage =
        @total_worked > 0 ? (worked.to_f / @total_worked * 100).round(2) : 0
      deviation = (worked - @average).round(2)

      {
        guide: balance.guide,
        worked: worked,
        percentage: percentage,
        deviation: deviation
      }
    end.sort_by { |d| -d[:worked] }

    # =====================================
    # 6️⃣ Datos para gráfico principal
    # =====================================

    @chart_data = @dashboard_data.map do |data|
      [data[:guide].name, data[:worked]]
    end

    # =====================================
    # 7️⃣ Selección de guía específica
    # =====================================

    @selected_guide =
      if params[:guide_id].present?
        @guides.find { |g| g.id == params[:guide_id].to_i }
      else
        @guides.first
      end

    # =====================================
    # 8️⃣ Histórico del guía seleccionado
    # =====================================

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