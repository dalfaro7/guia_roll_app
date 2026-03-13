class BusAssignmentsController < ApplicationController

  def create
    assignment = BusAssignment.new(bus_assignment_params)

    if assignment.save
      redirect_back fallback_location: work_day_path(assignment.work_day),
      notice: "Bus assigned successfully."
    else
      redirect_back fallback_location: root_path,
      alert: assignment.errors.full_messages.join(", ")
    end
  end

  def destroy
    assignment = BusAssignment.find(params[:id])
    work_day = assignment.work_day

    assignment.destroy

    redirect_to work_day_path(work_day),
    notice: "Bus removed."
  end

  private

  def bus_assignment_params
    params.require(:bus_assignment).permit(
      :bus_id,
      :work_day_id,
      :location,
      :seats_assigned
    )
  end

end


