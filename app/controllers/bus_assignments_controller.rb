class BusAssignmentsController < ApplicationController
  before_action :require_compensation_operator!, only: [:update]
  def create
    assignment = BusAssignment.new(bus_assignment_params)
    work_day = WorkDay.find_by(id: assignment.work_day_id)
    return redirect_to(work_days_path, alert: "Fecha inválida.") unless work_day

    if assignment.save
      redirect_to work_day_path(work_day), notice: "Bus asignado correctamente."
    else
      redirect_to work_day_path(work_day), alert: assignment.errors.full_messages.to_sentence
    end
  rescue ActiveRecord::RecordNotUnique
    redirect_to work_day_path(work_day), alert: "Este bus ya fue asignado en este día."
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
    assignment.destroy!
    redirect_to work_day_path(work_day), notice: "Bus retirado."
  end

  private

  def bus_assignment_params
    params.require(:bus_assignment).permit(:bus_id, :driver_id, :work_day_id,
      :location, :seats_assigned)
  end
end
