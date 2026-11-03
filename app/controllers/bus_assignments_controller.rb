class BusAssignmentsController < ApplicationController
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
