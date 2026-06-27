class DashboardController < ApplicationController
  def index
    # ==========================================================
    # 1. Mes seleccionado
    # ==========================================================
    @month = selected_month
    month_range = @month.beginning_of_month..@month.end_of_month

    # ==========================================================
    # 2. Parámetros de filtros
    # ==========================================================
    @selected_special_role = params[:special_role].presence || "all"

    # Estados que cuentan como asignación para el dashboard de equidad.
    # worked = trabajó en roll
    # assigned_task = tuvo tarea asignada por operaciones
    assigned_statuses = [:worked, :assigned_task]

    # ==========================================================
    # 3. Guías base
    # ==========================================================
    @guides = Guide.active.order(:name)

    # ==========================================================
    # 4. Conteo de asignaciones por guía
    # ==========================================================
    assigned_days_by_guide_id = GuideDay
      .joins(:work_day)
      .where(guide: @guides, status: assigned_statuses)
      .where(work_days: { date: month_range })
      .group(:guide_id)
      .count

    @assigned_work_slots = @guides.sum do |guide|
      assigned_days_by_guide_id[guide.id].to_i
    end

    @worked_month_days = GuideDay
      .joins(:work_day)
      .where(status: assigned_statuses)
      .where(work_days: { date: month_range })
      .distinct
      .count("work_days.date")

    @average =
      if @guides.any?
        (@assigned_work_slots.to_f / @guides.size).round(2)
      else
        0
      end

    # ==========================================================
    # 5. Datos principales del dashboard
    # ==========================================================
    @dashboard_data = @guides.map do |guide|
      worked = assigned_days_by_guide_id[guide.id].to_i

      percentage =
        @assigned_work_slots.positive? ? (worked.to_f / @assigned_work_slots * 100).round(2) : 0

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

    # ==========================================================
    # 6. Histórico por guía
    # ==========================================================
    @selected_guide =
      if params[:guide_id].present?
        @guides.find { |guide| guide.id == params[:guide_id].to_i } || @guides.first
      else
        @guides.first
      end

    @historical_data =
      if @selected_guide.present?
        GuideDay
          .joins(:work_day)
          .where(guide: @selected_guide, status: assigned_statuses)
          .group(Arel.sql("DATE_TRUNC('month', work_days.date)"))
          .order(Arel.sql("DATE_TRUNC('month', work_days.date)"))
          .count
          .map do |month_date, assigned_days|
            [
              month_date.strftime("%Y-%m"),
              assigned_days.to_i
            ]
          end
      else
        []
      end

    # ==========================================================
    # 7. Roles especiales
    # ==========================================================
    @special_role_data = build_special_role_data(month_range)

    @filtered_special_role_data = filter_special_role_data(
      @special_role_data,
      @selected_special_role
    )

    # Este arreglo debe usar la data filtrada para que el gráfico
    # responda al filtro seleccionado.
    @special_role_chart_data = @filtered_special_role_data.map do |data|
      {
        name: data[:guide_name],
        "Safety Kayaker": data[:safety_kayaker],
        "Photographer": data[:photographer],
        "Bus Guide": data[:bus_guide]
      }
    end
  end

  private

  # ==========================================================
  # Convierte params[:month] en Date.
  # Si el parámetro viene malo, usa el mes actual.
  # ==========================================================
  def selected_month
    return Date.today.beginning_of_month if params[:month].blank?

    year, month = params[:month].split("-").map(&:to_i)
    Date.new(year, month, 1)
  rescue
    Date.today.beginning_of_month
  end

  # ==========================================================
  # Construye el conteo de roles especiales por guía.
  #
  # Cuenta:
  # - Safety Kayaker en role_primary
  # - Photographer en role_primary
  # - Bus Guide en role_secondary
  # - Bus Guide & SendPhotos en role_secondary
  #
  # Solo cuenta GuideDays trabajados.
  # ==========================================================
  def build_special_role_data(month_range)
    special_role_rows = GuideDay
      .joins(:work_day, :guide)
      .where(work_days: { date: month_range })
      .where(status: :worked)
      .where(
  "guide_days.role_primary IN (?) OR guide_days.role_secondary LIKE ?",
  ["Safety Kayaker", "Photographer"],
  "Bus Guide%"
)
      .select(
        "guides.id AS guide_id",
        "guides.name AS guide_name",
        "guide_days.role_primary",
        "guide_days.role_secondary"
      )

    special_role_counts = Hash.new do |hash, guide_name|
      hash[guide_name] = {
        guide_name: guide_name,
        safety_kayaker: 0,
        photographer: 0,
        bus_guide: 0,
        total: 0
      }
    end

    special_role_rows.each do |row|
      guide_name = row.guide_name
      data = special_role_counts[guide_name]

      if row.role_primary == "Safety Kayaker"
        data[:safety_kayaker] += 1
        data[:total] += 1
      end

      if row.role_primary == "Photographer"
        data[:photographer] += 1
        data[:total] += 1
      end

      if row.role_secondary.to_s.start_with?("Bus Guide")
  data[:bus_guide] += 1
  data[:total] += 1
end
    end

    special_role_counts.values.sort_by { |data| -data[:total] }
  end

  # ==========================================================
  # Aplica el filtro seleccionado a la tabla y al gráfico.
  # ==========================================================
  def filter_special_role_data(data, selected_role)
    case selected_role
    when "safety_kayaker"
      data.select { |row| row[:safety_kayaker].to_i.positive? }
    when "photographer"
      data.select { |row| row[:photographer].to_i.positive? }
    when "bus_guide"
      data.select { |row| row[:bus_guide].to_i.positive? }
    else
      data
    end
  end
end