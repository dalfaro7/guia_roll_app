class WorkDaysController < ApplicationController
  before_action :set_work_day, only: [
    :show,
    :update_roles,
    :generate_roles,
    :publish,
    :unpublish,
    :reset_roll
  ]

  def index
    @work_days = WorkDay.order(date: :asc)
  end

  def show
    @guide_days = @work_day.guide_days.includes(:guide)
  end

  def new
    @work_day = WorkDay.new
  end

 

  def create
  @work_day = WorkDay.new(work_day_params)

  if WorkDay.exists?(date: @work_day.date)
    redirect_back fallback_location: work_days_path,
                  alert: "A Work Day already exists for this date."
    return
  end

  if @work_day.save
    redirect_to @work_day, notice: "Work Day created successfully."
  else
    redirect_back fallback_location: work_days_path,
                  alert: @work_day.errors.full_messages.join(", ")
  end
end


  def update
  @work_day = WorkDay.find(params[:id])

  if @work_day.update(work_day_params)
    redirect_to @work_day, notice: "Work day actualizado correctamente."
  else
    render :edit, status: :unprocessable_entity
  end
end

# =====================================
  # UPDATE availability
  # =====================================

def update_availability
  @work_day = WorkDay.find(params[:id])

  params[:availability]&.each do |guide_day_id, status|
    guide_day = @work_day.guide_days.find(guide_day_id)

    guide_day.update!(
      status: status,
      manually_modified: true
    )
  end

  redirect_to @work_day, notice: "Availability updated."
end

  # =====================================
  # UPDATE roles
  # =====================================

  def update_roles
  @work_day = WorkDay.find(params[:id])

  return redirect_to @work_day unless params[:roles]

  @work_day.guide_days.where(id: params[:roles].keys).each do |guide_day|

    role_data = params[:roles][guide_day.id.to_s]

    updates = {}

    if role_data["role_primary"].present?
      updates[:role_primary] = role_data["role_primary"]
    end

    if role_data["role_secondary"].present?
      updates[:role_secondary] = role_data["role_secondary"]
    end

    if role_data["location"].present?
      updates[:location] = role_data["location"]
    end

    guide_day.update(updates) if updates.any?
  end

  redirect_to @work_day, notice: "Roles updated successfully."
end

  # =====================================
  # GENERATE ROLES
  # =====================================
 def generate_roles
  work_day = WorkDay.find(params[:id])

  begin
    RoleGenerator.new(work_day).generate!
    flash[:notice] = "Generated"
  rescue => e
    flash[:alert] = e.message
  end

  redirect_to work_day_path(work_day)
end

  # =====================================
  # PUBLISH
  # =====================================
  def publish
    unless @work_day.generated?
      redirect_to @work_day, alert: "Only generated days can be published."
      return
    end

    worked_count = @work_day.guide_days.worked.count

    if worked_count != @work_day.guides_requested
      redirect_to @work_day, alert: "Assignments incomplete."
      return
    end

    @work_day.publish!
    redirect_to @work_day, notice: "Work day published."
  end

  # =====================================
  # UNPUBLISH
  # =====================================
  def unpublish
    if @work_day.published?
      @work_day.unpublish!
      redirect_to @work_day, notice: "Work day unpublished."
    else
      redirect_to @work_day, alert: "Only published days can be unpublished."
    end
  end

 # =====================================
# DELETE WORK DAY WITH BALANCE RESET
# =====================================
def delete_with_reset
  @work_day = WorkDay.find(params[:id])

  ActiveRecord::Base.transaction do
    month = @work_day.date.beginning_of_month

    # 1️⃣ Revertir balances solo de los worked
    @work_day.guide_days.worked.includes(:guide).each do |guide_day|
      guide = guide_day.guide

      balance = guide.monthly_balances.find_by(month: month)

      if balance&.worked_days.to_i > 0
        balance.decrement!(:worked_days)
      end

      if guide.total_worked_days.to_i > 0
        guide.decrement!(:total_worked_days)
      end
    end

    # 2️⃣ Eliminar versiones
    @work_day.work_day_versions.delete_all

    # 3️⃣ Eliminar guide_days
    @work_day.guide_days.delete_all

    # 4️⃣ Eliminar work_day
    @work_day.destroy!
  end

  redirect_to work_days_path,
              notice: "Work Day deleted and balances restored."
end


   # =====================================
  # RESET ROLL
  # =====================================
 def reset_roll
  @work_day.reset_roll!
  redirect_to @work_day, notice: "Roll reset. You may now set new availability."
end

  private

  def set_work_day
    @work_day = WorkDay.find(params[:id])
  end

  def work_day_params
  params.require(:work_day).permit(
    :date,
    :guides_requested,
    guide_days_attributes: [
      :id,
      :status,
      :role_primary,
      :role_secondary,
      :manually_modified
    ]
  )
end

end