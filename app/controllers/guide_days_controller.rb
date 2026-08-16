class GuideDaysController < ApplicationController
  before_action :set_guide_day, only: [:update]

  def update
    if @guide_day.update(guide_day_params)
      redirect_back(
        fallback_location: work_day_path(@guide_day.work_day),
        notice: "Guide role updated."
      )
    else
      redirect_back(
        fallback_location: work_day_path(@guide_day.work_day),
        alert: @guide_day.errors.full_messages.join(", ")
      )
    end
  end

  private

  def set_guide_day
    @guide_day = GuideDay.find(params[:id])
  end

  # Cualquier cambio manual de status queda persistido en GuideDay.
  #
  # Esto es importante porque RollFairnessPolicy utiliza
  # los GuideDay históricos como fuente real para determinar
  # las oportunidades de roll consumidas.
  def guide_day_params
    params.require(:guide_day).permit(
      :status,
      :role_primary,
      :role_secondary,
      :manually_modified
    )
  end
end