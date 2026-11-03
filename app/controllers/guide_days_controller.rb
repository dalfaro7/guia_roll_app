class GuideDaysController < ApplicationController
  before_action :set_guide_day, only: [:update]
  before_action :require_compensation_operator!, only: [:update]
  before_action :enforce_edit_window, only: [:update]

  def update
    before = @guide_day.attributes.slice("status", "role_primary", "role_secondary")
    GuideDay.transaction do
      @guide_day.update!(guide_day_params)
      audit!(action: "update_guide_day", auditable: @guide_day,
        work_day: @guide_day.work_day,
        metadata: { before: before,
          after: @guide_day.attributes.slice(*before.keys),
          reason: params[:correction_reason] })
    end
    redirect_back(fallback_location: work_day_path(@guide_day.work_day),
      notice: "Rol del guía actualizado.")
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, RuntimeError => e
    redirect_back(fallback_location: work_day_path(@guide_day.work_day),
      alert: e.message)
  end

  private

  def enforce_edit_window
    allowed = Compensation::EditWindow.allowed?(
      user: current_user, work_day: @guide_day.work_day
    )
    closed = Compensation::EditWindow.closed?(@guide_day.work_day)
    return if allowed && (!closed || !current_user.admin? ||
      params[:correction_reason].present?)

    redirect_to work_day_path(@guide_day.work_day),
      alert: allowed ? "Indique el motivo de la corrección." :
        "Esta programación ya cerró. Solo un administrador puede corregirla."
  end

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