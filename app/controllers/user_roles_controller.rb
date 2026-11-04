class UserRolesController < ApplicationController
  before_action :require_superadmin!

  def index
    @users = User.order(:name, :id)
  end

  def update
    target = User.find(params[:id])
    requested = params.require(:user).fetch(:access_role, "").to_s
    unless User::ACCESS_ROLE_LABELS.key?(requested)
      return redirect_to user_roles_path, alert: "Seleccione un rol válido."
    end
    if target.id == current_user.id
      return redirect_to user_roles_path,
        alert: "No puede cambiar su propio acceso desde esta página."
    end

    changed = false
    User.transaction do
      User.where(superadmin: true).order(:id).lock.load
      target.lock!
      before = target.access_role
      if before != requested
        if target.superadmin? && requested != "superadmin" &&
            User.where(superadmin: true).count <= 1
          target.errors.add(:base, "Debe quedar al menos un Super Admin")
          raise ActiveRecord::RecordInvalid, target
        end

        target.update!(role: requested == "superadmin" ? "admin" : requested,
          superadmin: requested == "superadmin")
        audit!(action: "update_user_role", auditable: target,
          metadata: { before: before, after: target.access_role })
        changed = true
      end
    end

    redirect_to user_roles_path,
      notice: changed ? "Rol de #{target.name} actualizado." : "El rol ya estaba asignado."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to user_roles_path, alert: e.record.errors.full_messages.to_sentence
  end
end
