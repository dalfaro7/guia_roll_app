require "set"

class RollFairnessPolicy
  # Si está en false:
  # assigned_task cuenta como servicio realizado,
  # pero NO consume una oportunidad del roll.
  #
  # Si en el futuro las tareas se pagan igual que una guiada,
  # cambiar esta bandera a true hará que assigned_task sí cuente
  # dentro del fairness del roll.
  ASSIGNED_TASK_COUNTS_AS_ROLL_WORK = false

  class << self
    # Devuelve la llave completa usada para ordenar candidatos.
    #
    # Orden de prioridad:
    # 1. Prioridad del guía
    # 2. Menos oportunidades consumidas del roll
    # 3. Menor racha consecutiva
    # 4. Mayor tiempo esperando una nueva guiada
    # 5. ID como desempate técnico estable
    def ranking_key_for(guide, before_date:)
      snapshot = fairness_snapshot_for(
        guide,
        before_date: before_date
      )

      [
        snapshot[:priority],
        snapshot[:roll_worked_days],
        snapshot[:consecutive_roll_days],
        snapshot[:waiting_since],
        guide.id
      ]
    end

    # Genera una fotografía del estado actual de fairness de un guía.
    #
    # Este método será útil tanto para el ranking como para
    # futuros diagnósticos de "por qué este guía fue seleccionado".
    def fairness_snapshot_for(guide, before_date:)
      fairness_start = fairness_start_for(
        guide,
        before_date: before_date
      )

      {
        guide_id: guide.id,
        guide_name: guide.name,
        priority: guide.priority || 999,
        fairness_started_on: fairness_start,
        roll_worked_days: roll_worked_days_for(
          guide,
          fairness_start: fairness_start,
          before_date: before_date
        ),
        consecutive_roll_days: consecutive_roll_work_days_for(
          guide,
          before_date: before_date
        ),
        waiting_since: waiting_since_for(
          guide,
          before_date: before_date
        )
      }
    end

    # Define si assigned_task debe consumir una oportunidad del roll.
    def assigned_task_counts_as_roll_work?
      ASSIGNED_TASK_COUNTS_AS_ROLL_WORK
    end

    # Estados que consumen fairness.
    #
    # Actualmente:
    # worked = sí
    # assigned_task = no
    def fairness_statuses
      statuses = [:worked]

      statuses << :assigned_task if assigned_task_counts_as_roll_work?

      statuses
    end

    # Estados que representan servicio realizado para estadísticas.
    #
    # Esto es independiente del fairness.
    def service_statuses
      [:worked, :assigned_task]
    end

    # Determina desde cuándo está esperando el guía una nueva guiada.
    #
    # Si ya obtuvo una guiada dentro de su ciclo actual,
    # usamos la fecha de la última.
    #
    # Si todavía no ha guiado desde que fue activado,
    # usamos fairness_started_on para evitar darle
    # antigüedad ficticia.
    def waiting_since_for(guide, before_date:)
      fairness_start = fairness_start_for(
        guide,
        before_date: before_date
      )

      last_roll_work_date =
        GuideDay
          .joins(:work_day)
          .where(
            guide: guide,
            status: fairness_statuses
          )
          .where(
            work_days: {
              date: fairness_start...before_date
            }
          )
          .maximum("work_days.date")

      last_roll_work_date || fairness_start
    end

    # Cuenta cuántos días consecutivos de roll lleva el guía
    # inmediatamente antes del WorkDay que se está generando.
    #
    # Ejemplo:
    # 14 ago = worked
    # 15 ago = worked
    # 16 ago = se genera
    #
    # Resultado: streak = 2
    def consecutive_roll_work_days_for(guide, before_date:)
      fairness_start = fairness_start_for(
        guide,
        before_date: before_date
      )

      roll_work_dates =
        GuideDay
          .joins(:work_day)
          .where(
            guide: guide,
            status: fairness_statuses
          )
          .where(
            work_days: {
              date: fairness_start...before_date
            }
          )
          .pluck("work_days.date")
          .to_set

      streak = 0
      date = before_date - 1.day

      while date >= fairness_start && roll_work_dates.include?(date)
        streak += 1
        date -= 1.day
      end

      streak
    end

    private

    # El ciclo de fairness empieza en fairness_started_on.
    #
    # Para guías antiguos que todavía no tengan este campo definido,
    # usamos el inicio del mes como fallback seguro.
    def fairness_start_for(guide, before_date:)
      guide.fairness_started_on || before_date.beginning_of_month
    end

    # Cuenta únicamente las oportunidades del roll consumidas
    # dentro del ciclo actual y antes del día que se está generando.
    def roll_worked_days_for(guide, fairness_start:, before_date:)
      return 0 if fairness_start >= before_date

      GuideDay
        .joins(:work_day)
        .where(
          guide: guide,
          status: fairness_statuses
        )
        .where(
          work_days: {
            date: fairness_start...before_date
          }
        )
        .count
    end
  end
end