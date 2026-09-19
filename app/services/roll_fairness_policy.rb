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
    # 2. Guía nuevo sin primera guiada, al final de su nivel
    # 3. Menos oportunidades consumidas del roll
    # 4. Menor racha consecutiva
    # 5. Estado del día anterior
    # 6. Mayor tiempo esperando una nueva guiada
    # 7. ID como desempate técnico estable
    def ranking_key_for(guide, before_date:)
      snapshot = fairness_snapshot_for(
        guide,
        before_date: before_date
      )

      [
        snapshot[:priority],
        new_entrant_rank_for(guide, before_date: before_date),
        snapshot[:ranking_roll_days],
        snapshot[:consecutive_roll_days],
        previous_day_status_rank_for(guide, before_date: before_date),
        snapshot[:waiting_since],
        guide.id
      ]
    end

    # Genera una fotografía del estado actual de fairness de un guía.
    #
    # roll_worked_days:
    #   Cuenta únicamente las guiadas que consumen fairness.
    #
    # service_days:
    #   Cuenta todos los días de servicio:
    #   worked + assigned_task.
    #
    # service_days es informativo y NO modifica el ranking.
    def fairness_snapshot_for(guide, before_date:)
      fairness_start = fairness_start_for(
        guide,
        before_date: before_date
      )

      roll_worked_days = roll_worked_days_for(
        guide,
        fairness_start: fairness_start,
        before_date: before_date
      )
      entry_balance = entry_roll_balance_for(guide, before_date: before_date)

      {
        guide_id: guide.id,
        guide_name: guide.name,
        priority: guide.priority || 999,
        fairness_started_on: fairness_start,

        roll_worked_days: roll_worked_days,
        entry_roll_balance: entry_balance,
        ranking_roll_days: roll_worked_days + entry_balance,

        service_days: service_days_for(
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

    # Estados que representan servicio realizado.
    #
    # Estos estados se utilizan para calcular Worked Days
    # en el Fairness Diagnosis.
    #
    # Esto es independiente del fairness utilizado para
    # seleccionar guías en el roll.
    def service_statuses
      [:worked, :assigned_task]
    end

    # Keep the fixed entry balance through the month of the first
    # roll assignment when that assignment occurs after activation month.
    def entry_roll_balance_for(guide, before_date:)
      start_date = guide.fairness_started_on
      return 0 if start_date.blank? || start_date > before_date

      if start_date.beginning_of_month == before_date.beginning_of_month
        return guide.fairness_entry_roll_days.to_i
      end

      first_roll_date = GuideDay
        .joins(:work_day)
        .where(guide: guide, status: fairness_statuses)
        .where(work_days: { date: start_date...before_date })
        .minimum("work_days.date")

      return 0 unless first_roll_date&.beginning_of_month == before_date.beginning_of_month

      guide.fairness_entry_roll_days.to_i
    end

    # A guide entering mid-month waits behind established guides
    # of the same priority until their first roll assignment.
    def new_entrant_rank_for(guide, before_date:)
      start_date = guide.fairness_started_on
      return 0 if start_date.blank?
      return 0 if start_date == start_date.beginning_of_month
      return 0 if start_date > before_date

      has_roll_work = GuideDay
        .joins(:work_day)
        .where(guide: guide, status: fairness_statuses)
        .where(work_days: { date: start_date...before_date })
        .exists?

      has_roll_work ? 0 : 1
    end

    # Tie break: standby, assigned task, day off, penalized.
    def previous_day_status_rank_for(guide, before_date:)
      status = GuideDay
        .joins(:work_day)
        .where(
          guide: guide,
          work_days: { date: before_date - 1.day }
        )
        .pick(:status)

      case status
      when "standby" then 0
      when "assigned_task" then 1
      when "day_off" then 2
      when "penalized" then 3
      else 2
      end
    end

    # Determina desde cuándo está esperando el guía
    # una nueva guiada.
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
    #
    # 14 ago = worked
    # 15 ago = worked
    # 16 ago = se genera
    #
    # Resultado:
    # consecutive_roll_days = 2
    #
    # assigned_task NO aumenta esta racha mientras
    # ASSIGNED_TASK_COUNTS_AS_ROLL_WORK sea false.
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
    # Para guías antiguos que todavía no tengan este campo
    # definido, usamos el inicio del mes como fallback seguro.
    def fairness_start_for(guide, before_date:)
  month_start = before_date.beginning_of_month

  guide_start = guide.fairness_started_on

  return month_start if guide_start.blank?

  [guide_start, month_start].max
end

    # Cuenta únicamente las oportunidades del roll consumidas
    # dentro del ciclo actual y antes del día que se está generando.
    #
    # Con la configuración actual esto equivale a:
    #
    # Guided Days = worked
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

    # Cuenta todos los días en los que el guía prestó servicio
    # dentro de su ciclo actual.
    #
    # Actualmente:
    #
    # Worked Days = worked + assigned_task
    #
    # Este valor es únicamente informativo.
    # NO participa en ranking_key_for.
    def service_days_for(guide, fairness_start:, before_date:)
      return 0 if fairness_start >= before_date

      GuideDay
        .joins(:work_day)
        .where(
          guide: guide,
          status: service_statuses
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