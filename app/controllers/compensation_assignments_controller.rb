class CompensationAssignmentsController < ApplicationController
  before_action :require_compensation_operator!
  before_action :set_work_day
  before_action :require_open_window

  def create
    departure = @work_day.departures.find(assignment_params[:departure_id])
    assignment = departure.compensation_assignments.new(assignment_params.except(:departure_id))
    assignment.updated_by = current_user
    assignment.principal_photographer = true if assignment.role_code == "photographer" &&
      !departure.compensation_assignments.active.where(principal_photographer: true).exists?

    Compensation::Current.set(actor: current_user, reason: params[:correction_reason]) do
      CompensationAssignment.transaction do
        assignment.save!
        Compensation::RepriceDay.call(@work_day)
        audit!(action: "create_compensation_assignment", auditable: assignment,
          work_day: @work_day, metadata: { reason: params[:correction_reason] })
      end
    end
    redirect_to work_day_compensation_path(@work_day), notice: "Asignación guardada."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, RuntimeError => e
    redirect_to work_day_compensation_path(@work_day), alert: e.message
  end

  def update
    assignment = assignment_for_day
    before = assignment.attributes.slice("role_code", "photo_task", "also_drives",
      "bus_guide", "principal_photographer", "status")

    Compensation::Current.set(actor: current_user, reason: params[:correction_reason]) do
      CompensationAssignment.transaction do
        changes = assignment_params.except(:departure_id, :guide_id, :driver_id)
          .merge(updated_by: current_user, source: "manual")
        if ActiveModel::Type::Boolean.new.cast(changes[:principal_photographer]) &&
            changes[:role_code] == "photographer"
          previous_principals = assignment.departure.compensation_assignments.active
            .where(role_code: "photographer", principal_photographer: true)
            .where.not(id: assignment.id)
            .to_a
          previous_principals.each do |previous|
            previous.update_columns(principal_photographer: false,
              updated_by_id: current_user.id, updated_at: Time.current)
            audit!(action: "transfer_principal_photographer", auditable: previous,
              work_day: @work_day,
              metadata: { principal_photographer: false,
                new_principal_assignment_id: assignment.id,
                reason: params[:correction_reason] })
          end
        end
        assignment.update!(changes)
        sync_guide_day_role!(assignment)
        ensure_principal_photographer!(assignment.departure)
        Compensation::RepriceDay.call(@work_day)
        audit!(action: "update_compensation_assignment", auditable: assignment,
          work_day: @work_day,
          metadata: { before: before, after: assignment.attributes.slice(*before.keys),
            reason: params[:correction_reason] })
      end
    end
    redirect_to assignment_return_path, notice: "Asignación actualizada."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, RuntimeError => e
    redirect_to assignment_return_path, alert: e.message
  end

  def destroy
    assignment = assignment_for_day
    Compensation::Current.set(actor: current_user, reason: params[:correction_reason]) do
      CompensationAssignment.transaction do
        assignment.update!(status: "canceled", updated_by: current_user, source: "manual")
        ensure_principal_photographer!(assignment.departure)
        Compensation::RepriceDay.call(@work_day)
        audit!(action: "remove_compensation_assignment", auditable: assignment,
          work_day: @work_day, metadata: { reason: params[:correction_reason] })
      end
    end
    redirect_to work_day_compensation_path(@work_day), notice: "Asignación retirada."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, RuntimeError => e
    redirect_to work_day_compensation_path(@work_day), alert: e.message
  end

  private

  def set_work_day
    @work_day = WorkDay.find(params[:work_day_id])
  end

  def assignment_return_path
    params[:return_to] == "schedule" ? work_day_path(@work_day, anchor: @work_day.generated? ? "day-roles" : "day-assigned") :
      work_day_compensation_path(@work_day)
  end

  def assignment_for_day
    CompensationAssignment.joins(:departure)
      .where(departures: { work_day_id: @work_day.id }).find(params[:id])
  end

  def assignment_params
    params.require(:compensation_assignment).permit(
      :departure_id, :guide_id, :driver_id, :role_code, :photo_task,
      :also_drives, :bus_guide, :principal_photographer, :status
    )
  end

  def sync_guide_day_role!(assignment)
    guide_day = assignment.guide_day
    return unless assignment.guide? && guide_day&.worked?

    primary = case assignment.role_code
    when "photographer" then "Photographer"
    when "safety_kayak" then "Safety Kayaker"
    else "River Guide"
    end
    secondary = case assignment.role_code
    when "tl_balsa", "tl_sara" then "Tour Leader"
    when "hg_balsa", "hg_sara" then "Head Guide"
    else
      ["Tour Leader", "Head Guide"].include?(guide_day.role_secondary) ? nil :
        guide_day.role_secondary
    end
    return if guide_day.role_primary == primary && guide_day.role_secondary == secondary

    before = guide_day.attributes.slice("role_primary", "role_secondary")
    guide_day.update!(role_primary: primary, role_secondary: secondary,
      manually_modified: true, modified_by: current_user)
    audit!(action: "sync_schedule_role_from_compensation", auditable: guide_day,
      work_day: @work_day, metadata: { before: before,
        after: guide_day.attributes.slice("role_primary", "role_secondary"),
        reason: params[:correction_reason] })
  end

  def ensure_principal_photographer!(departure)
    photographers = departure.compensation_assignments.active
      .where(role_code: "photographer")
    return if !photographers.exists? || photographers.where(principal_photographer: true).exists?

    photographers.order(:id).first.update!(principal_photographer: true,
      updated_by: current_user)
    audit!(action: "assign_principal_photographer",
      auditable: photographers.order(:id).first, work_day: @work_day,
      metadata: { reason: params[:correction_reason] })
  end

  def require_open_window
    unless Compensation::EditWindow.applicable?(@work_day)
      redirect_to assignment_return_path,
        alert: "La valoración económica aún no aplica a esta fecha."
      return
    end
    return if Compensation::EditWindow.allowed?(user: current_user, work_day: @work_day) &&
      (!requires_reason? || params[:correction_reason].present?)

    redirect_to assignment_return_path,
      alert: requires_reason? ? "Indique el motivo de la corrección." :
        "Esta programación ya cerró. Solo un administrador puede corregirla."
  end

  def requires_reason?
    current_user.admin? && Compensation::EditWindow.closed?(@work_day)
  end
end
