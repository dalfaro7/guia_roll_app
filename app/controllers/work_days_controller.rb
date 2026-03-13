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
    @work_days = WorkDay.order(date: :desc)
  end

  def show
    @guide_days = @work_day.guide_days.includes(:guide)
     @location_counts = @work_day
                         .location_slots
                         .group(:location)
                         .count

    @passenger_counts = @work_day.location_slots
                                .pluck(:location, :passengers)
                                .to_h
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
  # forzar el primer stand by para entrar al rol
  # =====================================
  def force_assign
    work_day = WorkDay.find(params[:id])
    location = params[:location]
    skills = params[:skills] || []

    service = ForceAssignmentService.new(work_day, location, skills)

    begin
      service.call
      guide_name = service.guide.name

      redirect_to work_day_path(work_day),
                  notice: "#{guide_name} was forced into #{location}"

    rescue => e
      redirect_to work_day_path(work_day), alert: e.message
    end
  end

  # =====================================
  # siguiente en roll vista previa
  # =====================================
  def preview_force_assign

    work_day = WorkDay.find(params[:id])
    skill_ids = (params[:skills] || []).map(&:to_i)

    candidates = GuideDay
                  .available_for_date(work_day.date)
                  .where(work_day: work_day)
                  .includes(guide: :skills)
                  .joins(:guide)
                  .order("guides.priority ASC")

    guide_day = candidates.find do |gd|

      guide_skill_ids = gd.guide.skills.pluck(:id)

      (skill_ids - guide_skill_ids).empty?

    end

    if guide_day
      render json: {
        name: guide_day.guide.name,
        priority: guide_day.guide.priority
      }
    else
      render json: { name: nil }
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
      RoleGeneratorV2.new(work_day).generate!
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

      @work_day.work_day_versions.delete_all
      @work_day.guide_days.delete_all
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

  def locations
    @work_day = WorkDay.find(params[:id])

    @location_counts = @work_day
                         .location_slots
                         .group(:location)
                         .count

    @passenger_counts = @work_day.location_slots
                                .pluck(:location, :passengers)
                                .to_h
  end

  def create_slots
  @work_day = WorkDay.find(params[:id])

  @work_day.location_slots.destroy_all

  total_slots = 0

  params[:locations].each do |location, data|

    guides = data[:guides].to_i
    passengers = data[:passengers].to_i

    guides.times do

      slot = @work_day.location_slots.create!(
        location: location,
        passengers: passengers
      )

      default_skill = Skill.find_by(name: "ClassIII")
      slot.slot_skills.create!(skill: default_skill) if default_skill

      total_slots += 1

    end

  end

  @work_day.update!(guides_requested: total_slots)

  redirect_to @work_day, notice: "Slots created successfully."
end

  def edit_slots
    @work_day = WorkDay.find(params[:id])
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