class DeparturesController < ApplicationController
  before_action :require_compensation_operator!
  before_action :set_work_day
  before_action :require_open_window

  def update
    departure = @work_day.departures.find(params[:id])
    requested = params.require(:departure)
    unless requested.keys == ["status"] && requested[:status] == "canceled"
      raise ArgumentError, "Solo se permite cancelar la salida; su horario no se puede modificar."
    end
    Compensation::Current.set(actor: current_user, reason: params[:correction_reason]) do
      Departure.transaction do
        departure.lock!
        unless departure.status == "scheduled"
          raise ArgumentError, "Solo se puede cancelar una salida programada."
        end

        before = departure.attributes.slice("label", "location", "starts_at", "status")
        departure.update!(status: "canceled")
        departure.compensation_assignments.where(status: "planned")
          .update_all(status: "canceled", updated_at: Time.current)
        Compensation::RepriceDay.call(@work_day)
        audit!(action: "update_departure", auditable: departure, work_day: @work_day,
          metadata: { before: before,
            after: departure.attributes.slice(*before.keys), reason: params[:correction_reason] })
      end
    end
    redirect_to work_day_compensation_path(@work_day), notice: "Salida cancelada."
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    redirect_to work_day_compensation_path(@work_day), alert: e.message
  end

  private

  def set_work_day
    @work_day = WorkDay.find(params[:work_day_id])
  end

  def require_open_window
    unless Compensation::EditWindow.applicable?(@work_day)
      redirect_to work_day_compensation_path(@work_day),
        alert: "La valoración económica aún no aplica a esta fecha."
      return
    end
    return if Compensation::EditWindow.allowed?(user: current_user, work_day: @work_day) &&
      (!requires_reason? || params[:correction_reason].present?)

    redirect_to work_day_compensation_path(@work_day),
      alert: requires_reason? ? "Indique el motivo de la corrección." :
        "Esta programación ya cerró. Solo un administrador puede corregirla."
  end

  def requires_reason?
    current_user.admin? && Compensation::EditWindow.closed?(@work_day)
  end
end
