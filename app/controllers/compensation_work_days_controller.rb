class CompensationWorkDaysController < ApplicationController
  before_action :require_compensation_view!

  def show
    @work_day = WorkDay.find(params[:work_day_id])
    @departures = @work_day.departures.chronological
      .includes(compensation_assignments: [:guide, :driver, :compensation_lines])
    @guides = Guide.active.order(:name)
    @drivers = Driver.active.order(:name)
    @can_edit = Compensation::EditWindow.allowed?(
      user: current_user, work_day: @work_day
    )
  end
end
