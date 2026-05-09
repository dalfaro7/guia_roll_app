class ApplicationController < ActionController::Base
  before_action :authenticate_user!
  before_action :configure_permitted_parameters, if: :devise_controller?
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  def dummy
  render plain: "OK"
  end

  private

def audit!(action:, auditable:, work_day: nil, metadata: {})
  AuditLog.create!(
    user: current_user,
    action: action,
    auditable_type: auditable.class.name,
    auditable_id: auditable.id,
    work_day: work_day,
    metadata: {
      screen: params[:audit_screen],
      component: params[:audit_component],
      controller: controller_name,
      controller_action: action_name,
      request_method: request.method,
      path: request.fullpath,
      ip: request.remote_ip,
      user_agent: request.user_agent,
      performed_at: Time.current
    }.merge(metadata)
  )
end


protected

def configure_permitted_parameters
  devise_parameter_sanitizer.permit(
    :sign_up,
    keys: [:name]
  )

  devise_parameter_sanitizer.permit(
    :account_update,
    keys: [:name]
  )
end

end
