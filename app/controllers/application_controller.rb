class ApplicationController < ActionController::Base
  before_action :authenticate_user!
  before_action :restrict_hg_sarapiqui_scope!
  before_action :configure_permitted_parameters,
                if: :devise_controller?
  around_action :with_compensation_context

  allow_browser versions: :modern
  stale_when_importmap_changes

  def dummy
    render plain: "OK"
  end

  private

  def restrict_hg_sarapiqui_scope!
    return unless current_user&.hg_sarapiqui?
    return if devise_controller? && controller_name == "sessions" && action_name == "destroy"
    return if devise_controller? && controller_name == "registrations" &&
      %w[edit update].include?(action_name)

    allowed = {
      "work_days" => %w[sara sara_operation create_sara
        update_sara_availability assign_sara_guide add_sara_guide],
      "sara_guides" => %w[index new create edit update toggle_active]
    }
    return if allowed.fetch(controller_name, []).include?(action_name)

    redirect_to sara_work_days_path, alert: "HG Sarapiquí solo puede gestionar Sara y PM."
  end

  def after_sign_in_path_for(resource)
    resource.hg_sarapiqui? ? sara_work_days_path : super
  end

  def require_sara_operator!
    return if current_user&.admin? || current_user&.operador? ||
      current_user&.hg_sarapiqui?

    redirect_to root_path, alert: "No tiene permiso para gestionar Sara y PM."
  end

  def with_compensation_context
    Compensation::Current.set(
      actor: current_user,
      reason: params[:correction_reason].to_s.strip.presence
    ) { yield }
  end

  def require_admin!
    return if current_user&.admin?

    redirect_to root_path,
                alert: "Solo los administradores pueden realizar esta acción."
  end

  def require_superadmin!
    return if current_user&.admin? && current_user&.superadmin?

    redirect_to root_path, alert: "Solo Super Admin puede gestionar roles."
  end

  def require_rates_page_key!
    return if current_user && session[:compensation_rates_unlocked_user_id] == current_user.id

    redirect_to unlock_compensation_rates_path,
                alert: "Ingrese la clave para abrir Tarifas."
  end

  def require_compensation_view!
    return if current_user&.admin? || current_user&.operador? ||
              current_user&.contabilidad?

    redirect_to root_path, alert: "No tiene acceso a la valoración económica."
  end

  def require_compensation_payment!
    return if current_user&.admin? || current_user&.contabilidad?

    redirect_to root_path, alert: "Solo Contabilidad puede registrar pagos."
  end

  def require_compensation_operator!
    return if current_user&.admin? || current_user&.operador?

    redirect_to root_path, alert: "No tiene permiso para editar asignaciones."
  end

  def require_office_access!
    return if current_user&.admin? ||
              current_user&.recursos_humanos?

    redirect_to root_path,
                alert: "No tiene acceso al módulo Libres Oficina."
  end

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
