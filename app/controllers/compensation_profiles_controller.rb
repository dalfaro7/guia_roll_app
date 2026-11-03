class CompensationProfilesController < ApplicationController
  before_action :require_admin!

  def index
    @guides = Guide.order(:name)
  end

  def update
    guide = Guide.find(params[:id])
    before = guide.attributes.slice("pay_category")
    guide.update!(profile_params.merge(pay_category: profile_params[:pay_category].presence))
    audit!(action: "update_compensation_profile", auditable: guide,
      metadata: { before: before,
        after: guide.attributes.slice(*before.keys) })
    redirect_to compensation_profiles_path, notice: "Perfil económico actualizado."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to compensation_profiles_path,
      alert: e.record.errors.full_messages.to_sentence
  end

  private

  def profile_params
    params.require(:guide).permit(:pay_category)
  end
end
