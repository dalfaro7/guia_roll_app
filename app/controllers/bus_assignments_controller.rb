class BusAssignmentsController < ApplicationController
  before_action :require_compensation_operator!, only: [:create, :update, :destroy]

  def create
    assignment = BusAssignment.new(bus_assignment_params)
    work_day = WorkDay.find_by(id: assignment.work_day_id)
    return redirect_to(work_days_path, alert: "Fecha inválida.") unless work_day
    return unless editable_transport?(work_day)

    BusAssignment.transaction do
      work_day.lock!
      assignment.save!
      audit!(action: "create_transport_assignment", auditable: assignment,
        work_day: work_day,
        metadata: { bus_id: assignment.bus_id, driver_id: assignment.driver_id,
          location: assignment.location, outing_variant: assignment.outing_variant,
          cost_cents: assignment.cost_cents,
          driver_payment_cents: assignment.driver_payment_cents })
    end
    redirect_to work_day_path(work_day), notice: "Vehículo asignado correctamente."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to work_day_path(work_day), alert: e.record.errors.full_messages.to_sentence
  rescue ActiveRecord::RecordNotUnique
    redirect_to work_day_path(work_day), alert: "Este vehículo o chofer ya fue asignado a esta salida."
  end

  def update
    assignment = BusAssignment.find(params[:id])
    work_day = assignment.work_day
    unless Compensation::EditWindow.allowed?(user: current_user, work_day: work_day)
      return redirect_to work_day_path(work_day),
        alert: "La edición de costos de esta fecha ya cerró."
    end
    reason = params[:correction_reason].to_s.strip
    if current_user.admin? && Compensation::EditWindow.closed?(work_day) && reason.blank?
      return redirect_to work_day_path(work_day), alert: "Indique el motivo de la corrección."
    end

    before_cents = assignment.cost_cents
    BusAssignment.transaction do
      assignment.update!(cost_usd: params.require(:bus_assignment).fetch(:cost_usd, nil))
      audit!(action: "update_bus_cost", auditable: assignment, work_day: work_day,
        metadata: { before_cents: before_cents, after_cents: assignment.cost_cents,
          reason: reason.presence })
    end
    redirect_to work_day_path(work_day), notice: "Costo del transporte actualizado."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to work_day_path(work_day), alert: e.record.errors.full_messages.to_sentence
  end

  def destroy
    assignment = BusAssignment.find(params[:id])
    work_day = assignment.work_day
    return unless editable_transport?(work_day)

    BusAssignment.transaction do
      work_day.lock!
      before = assignment.attributes.slice("bus_id", "driver_id", "location",
        "outing_variant", "cost_cents", "compensation_assignment_id")
      assignment.destroy!
      audit!(action: "remove_transport_assignment", auditable: assignment,
        work_day: work_day, metadata: { before: before })
    end
    redirect_to work_day_path(work_day), notice: "Vehículo retirado."
  rescue ActiveRecord::RecordNotDestroyed => e
    redirect_to work_day_path(work_day), alert: e.record.errors.full_messages.to_sentence
  end

  private

  def editable_transport?(work_day)
    return true if Compensation::EditWindow.allowed?(user: current_user,
      work_day: work_day) &&
      (!Compensation::EditWindow.closed?(work_day) ||
        params[:correction_reason].present?)

    redirect_to work_day_path(work_day),
      alert: "La edición de esta fecha cerró. Un administrador debe indicar el motivo."
    false
  end

  def bus_assignment_params
    params.require(:bus_assignment).permit(:bus_id, :driver_id, :work_day_id,
      :location, :outing_variant, :seats_assigned)
  end
end
