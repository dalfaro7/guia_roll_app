class DashboardController < ApplicationController

  # ==========================================================
  # DASHBOARD PRINCIPAL
  # ==========================================================
  def index

    # ========================================================
    # 1. MES SELECCIONADO
    #
    # Este mes controla las métricas principales:
    # - días con asignaciones
    # - puestos asignados
    # - promedio
    # - distribución por guía
    # - roles especiales
    # ========================================================
    @month = selected_month

    month_range =
      @month.beginning_of_month..
      @month.end_of_month


    # ========================================================
    # 2. FILTRO DE ROLES ESPECIALES
    # ========================================================
    @selected_special_role =
      params[:special_role].presence || "all"


    # ========================================================
    # 3. ESTADOS QUE CUENTAN COMO SERVICIO REALIZADO
    #
    # RollFairnessPolicy centraliza esta regla.
    #
    # Actualmente incluye:
    # - worked
    # - assigned_task
    #
    # Esto permite que assigned_task cuente en el dashboard
    # como servicio prestado, aunque pueda tener una política
    # distinta dentro del fairness del roll.
    # ========================================================
    assigned_statuses =
      RollFairnessPolicy.service_statuses


    # ========================================================
    # 4. GUÍAS ACTIVOS
    #
    # El dashboard operativo principal solo muestra
    # guías actualmente activos.
    # ========================================================
    @guides =
      Guide.active.order(:name)


    # ========================================================
    # 5. ASIGNACIONES POR GUÍA DURANTE EL MES
    #
    # GuideDay es la fuente de verdad.
    #
    # Ya no utilizamos MonthlyBalance para calcular
    # las asignaciones reales.
    # ========================================================
    assigned_days_by_guide_id =
      GuideDay
        .joins(:work_day)
        .where(
          guide: @guides,
          status: assigned_statuses
        )
        .where(
          work_days: {
            date: month_range
          }
        )
        .group(:guide_id)
        .count


    # ========================================================
    # 6. TOTAL DE PUESTOS DE TRABAJO ASIGNADOS
    #
    # Ejemplo:
    #
    # Día 1: 15 guías
    # Día 2: 20 guías
    #
    # Total = 35 puestos asignados
    # ========================================================
    @assigned_work_slots =
      @guides.sum do |guide|
        assigned_days_by_guide_id[
          guide.id
        ].to_i
      end


    # ========================================================
    # 7. DÍAS DEL MES CON ALGUNA ASIGNACIÓN
    #
    # Cuenta fechas distintas.
    #
    # No importa si ese día trabajaron 5 o 30 guías:
    # la fecha cuenta solamente una vez.
    # ========================================================
    @worked_month_days =
      GuideDay
        .joins(:work_day)
        .where(
          status: assigned_statuses
        )
        .where(
          work_days: {
            date: month_range
          }
        )
        .distinct
        .count("work_days.date")


    # ========================================================
    # 8. PROMEDIO DE PUESTOS POR GUÍA
    # ========================================================
    @average =
      if @guides.any?
        (
          @assigned_work_slots.to_f /
          @guides.size
        ).round(2)
      else
        0
      end


    # ========================================================
    # 9. DATA PRINCIPAL POR GUÍA
    #
    # Incluye:
    # - cantidad de asignaciones
    # - porcentaje de participación
    # - desviación respecto al promedio
    # ========================================================
    @dashboard_data =
      @guides.map do |guide|

        worked =
          assigned_days_by_guide_id[
            guide.id
          ].to_i

        percentage =
          if @assigned_work_slots.positive?
            (
              worked.to_f /
              @assigned_work_slots *
              100
            ).round(2)
          else
            0
          end

        deviation =
          (
            worked -
            @average
          ).round(2)

        {
          guide: guide,
          worked: worked,
          percentage: percentage,
          deviation: deviation
        }

      end.sort_by do |data|

        [
          -data[:worked],
          data[:guide].name
        ]

      end


    # ========================================================
    # 10. DATA PARA GRÁFICO PRINCIPAL
    # ========================================================
    @chart_data =
      @dashboard_data.map do |data|
        [
          data[:guide].name,
          data[:worked]
        ]
      end


    # ========================================================
    # 11. GUÍA SELECCIONADO PARA HISTÓRICO
    # ========================================================
    @selected_guide =
      if params[:guide_id].present?

        @guides.find do |guide|
          guide.id ==
            params[:guide_id].to_i
        end || @guides.first

      else

        @guides.first

      end


    # ========================================================
    # 12. HISTÓRICO POR GUÍA
    #
    # También utiliza GuideDay como fuente de verdad.
    #
    # Agrupa asignaciones por mes.
    # ========================================================
    @historical_data =
      if @selected_guide.present?

        GuideDay
          .joins(:work_day)
          .where(
            guide: @selected_guide,
            status: assigned_statuses
          )
          .group(
            Arel.sql(
              "DATE_TRUNC('month', work_days.date)"
            )
          )
          .order(
            Arel.sql(
              "DATE_TRUNC('month', work_days.date)"
            )
          )
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


    # ========================================================
    # 13. ROLES ESPECIALES
    #
    # Safety Kayaker
    # Photographer
    # Bus Guide
    # ========================================================
    @special_role_data =
      build_special_role_data(
        month_range
      )


    # Aplica el filtro seleccionado.
    @filtered_special_role_data =
      filter_special_role_data(
        @special_role_data,
        @selected_special_role
      )


    # ========================================================
    # 14. DATA PARA GRÁFICO DE ROLES ESPECIALES
    # ========================================================
    @special_role_chart_data =
      @filtered_special_role_data.map do |data|

        {
          name: data[:guide_name],
          "Safety Kayaker": data[:safety_kayaker],
          "Photographer": data[:photographer],
          "Bus Guide": data[:bus_guide]
        }

      end


    # ========================================================
    # 15. INCIDENTES OPERACIONALES
    #
    # Se mantiene independiente de:
    # - fairness
    # - MonthlyBalance
    # - días trabajados
    #
    # RollNote es su propia fuente de información.
    # ========================================================
    build_incident_data

  end


  private


  # ==========================================================
  # MES SELECCIONADO
  #
  # Convierte params[:month]:
  #
  # "2026-08"
  #
  # en:
  #
  # Date.new(2026, 8, 1)
  #
  # Si el parámetro es inválido utiliza el mes actual.
  # ==========================================================
  def selected_month

    return Date.current.beginning_of_month if
      params[:month].blank?

    year, month =
      params[:month]
        .split("-")
        .map(&:to_i)

    Date.new(
      year,
      month,
      1
    )

  rescue ArgumentError

    Date.current.beginning_of_month

  end


  # ==========================================================
  # ROLES ESPECIALES
  #
  # Cuenta:
  #
  # role_primary:
  # - Safety Kayaker
  # - Photographer
  #
  # role_secondary:
  # - cualquier valor que empiece con "Bus Guide"
  #
  # Solo GuideDay worked.
  # ==========================================================
  def build_special_role_data(month_range)

    special_role_rows =
      GuideDay
        .joins(
          :work_day,
          :guide
        )
        .where(
          work_days: {
            date: month_range
          }
        )
        .where(
          status: :worked
        )
        .where(
          "guide_days.role_primary IN (?) " \
          "OR guide_days.role_secondary LIKE ?",
          [
            "Safety Kayaker",
            "Photographer"
          ],
          "Bus Guide%"
        )
        .select(
          "guides.id AS guide_id",
          "guides.name AS guide_name",
          "guide_days.role_primary",
          "guide_days.role_secondary"
        )


    # Hash que crea automáticamente una estructura
    # inicial para cada guía encontrado.
    special_role_counts =
      Hash.new do |hash, guide_name|

        hash[guide_name] = {
          guide_name: guide_name,
          safety_kayaker: 0,
          photographer: 0,
          bus_guide: 0,
          total: 0
        }

      end


    special_role_rows.each do |row|

      data =
        special_role_counts[
          row.guide_name
        ]


      # Safety Kayaker
      if row.role_primary ==
         "Safety Kayaker"

        data[:safety_kayaker] += 1
        data[:total] += 1

      end


      # Photographer
      if row.role_primary ==
         "Photographer"

        data[:photographer] += 1
        data[:total] += 1

      end


      # Bus Guide
      if row.role_secondary
            .to_s
            .start_with?("Bus Guide")

        data[:bus_guide] += 1
        data[:total] += 1

      end

    end


    # Orden:
    # quien tenga más asignaciones especiales primero.
    special_role_counts
      .values
      .sort_by do |data|

        -data[:total]

      end

  end


  # ==========================================================
  # FILTRO DE ROLES ESPECIALES
  # ==========================================================
  def filter_special_role_data(
    data,
    selected_role
  )

    case selected_role

    when "safety_kayaker"

      data.select do |row|
        row[
          :safety_kayaker
        ].to_i.positive?
      end


    when "photographer"

      data.select do |row|
        row[
          :photographer
        ].to_i.positive?
      end


    when "bus_guide"

      data.select do |row|
        row[
          :bus_guide
        ].to_i.positive?
      end


    else

      data

    end

  end


  # ==========================================================
  # INCIDENTES OPERACIONALES
  #
  # Construye:
  #
  # @incident_year
  # @incident_month
  # @incident_years
  # @incidents_by_guide
  # @incidents_by_month
  #
  # IMPORTANTE:
  #
  # Un incidente asociado a 3 guías cuenta:
  #
  # +1 para cada guía involucrado
  #
  # pero únicamente:
  #
  # +1 incidente total para el gráfico mensual.
  # ==========================================================
  def build_incident_data

    # ========================================================
    # AÑO SELECCIONADO
    # ========================================================
    @incident_year =
      if params[
           :incident_year
         ].present?

        params[
          :incident_year
        ].to_i

      else

        Date.current.year

      end


    # ========================================================
    # MES SELECCIONADO
    #
    # nil = todos los meses
    # ========================================================
    @incident_month =
      if params[
           :incident_month
         ].present?

        params[
          :incident_month
        ].to_i

      else

        nil

      end


    # ========================================================
    # RANGO PARA INCIDENTES POR GUÍA
    #
    # Si hay mes:
    #
    #   solamente ese mes.
    #
    # Si no:
    #
    #   todo el año.
    # ========================================================
    incident_range =
      if @incident_month.present? &&
         @incident_month.between?(1, 12)

        Date.new(
          @incident_year,
          @incident_month,
          1
        ).all_month

      else

        Date.new(
          @incident_year,
          1,
          1
        )..
        Date.new(
          @incident_year,
          12,
          31
        )

      end


    # ========================================================
    # INCIDENTES POR GUÍA
    #
    # Relaciones:
    #
    # RollNote
    #   ↓
    # RollNoteGuideDay
    #   ↓
    # GuideDay
    #   ↓
    # Guide
    #
    # Solamente notas de tipo incident.
    # ========================================================
    incident_counts_by_guide =
      RollNote
        .incident
        .joins(
          roll_note_guide_days: {
            guide_day: [
              :guide,
              :work_day
            ]
          }
        )
        .where(
          work_days: {
            date: incident_range
          }
        )
        .group(
          "guides.id",
          "guides.name"
        )
        .count


    # ========================================================
    # FORMATO PARA CHARTKICK
    #
    # [
    #   ["Tom Leon Oviedo", 3],
    #   ["Juan Perez", 2]
    # ]
    #
    # Ordenado de mayor a menor.
    # ========================================================
    @incidents_by_guide =
      incident_counts_by_guide
        .map do |key, count|

          guide_id,
          guide_name =
            key

          [
            guide_name,
            count
          ]

        end
        .sort_by do |guide_name, count|

          [
            -count,
            guide_name
          ]

        end


    # ========================================================
    # RANGO COMPLETO DEL AÑO
    #
    # El gráfico mensual siempre muestra enero-diciembre,
    # aunque el filtro de arriba tenga un mes específico.
    # ========================================================
    year_range =
      Date.new(
        @incident_year,
        1,
        1
      )..
      Date.new(
        @incident_year,
        12,
        31
      )


    # ========================================================
    # INCIDENTES TOTALES POR MES
    #
    # Aquí NO hacemos join con guías.
    #
    # Esto evita que un incidente con tres guías
    # se cuente como tres incidentes.
    # ========================================================
    monthly_incident_counts =
      RollNote
        .incident
        .joins(:work_day)
        .where(
          work_days: {
            date: year_range
          }
        )
        .group(
          Arel.sql(
            "EXTRACT(MONTH FROM work_days.date)"
          )
        )
        .count


    # ========================================================
    # GENERAR LOS 12 MESES
    #
    # Incluso meses sin incidentes aparecen con 0.
    # ========================================================
    @incidents_by_month =
      (1..12).map do |month_number|

        count =
          monthly_incident_counts[
            month_number.to_f
          ].to_i

        [
          Date::ABBR_MONTHNAMES[
            month_number
          ],
          count
        ]

      end


    # ========================================================
    # AÑOS DISPONIBLES
    #
    # Lee los años donde existen RollNotes.
    # ========================================================
    @incident_years =
      RollNote
        .joins(:work_day)
        .distinct
        .pluck(
          Arel.sql(
            "EXTRACT(YEAR FROM work_days.date)"
          )
        )
        .map(&:to_i)


    # Siempre incluir el año actual aunque todavía
    # no tenga incidentes.
    unless @incident_years.include?(
      Date.current.year
    )

      @incident_years <<
        Date.current.year

    end


    # El más reciente primero.
    @incident_years =
      @incident_years
        .uniq
        .sort
        .reverse

  end

end