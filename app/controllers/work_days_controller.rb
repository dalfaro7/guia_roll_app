class WorkDaysController < ApplicationController
  before_action :set_work_day, only: [
    :show,
    :update_roles,
    :generate_roles,
    :publish,
    :unpublish,
    :reset_roll,
    :move_assigned_task_to_roll
  ]

  def index
    if params[:start_date].present? && params[:end_date].present?
      @work_days =
        WorkDay
          .where(date: params[:start_date]..params[:end_date])
          .order(date: :desc)
    else
      @work_days =
        WorkDay
          .where(
            date: (Date.current - 7.days)..(Date.current + 1.day)
          )
          .order(date: :desc)
    end
  end

  def show
    @guide_days = @work_day.guide_days.includes(:guide)

    @location_counts =
      @work_day
        .location_slots
        .group(:location)
        .count

    @passenger_counts =
      @work_day
        .location_slots
        .group(:location)
        .maximum(:passengers)
  end

  def new
    @work_day = WorkDay.new
  end

  def create
    @work_day = WorkDay.new(work_day_params)

    if WorkDay.exists?(date: @work_day.date)
      redirect_back(
        fallback_location: work_days_path,
        alert: "A Work Day already exists for this date."
      )
      return
    end

    if @work_day.save
      redirect_to(
        @work_day,
        notice: "Work Day created successfully."
      )
    else
      redirect_back(
        fallback_location: work_days_path,
        alert: @work_day.errors.full_messages.join(", ")
      )
    end
  end

  def update
    @work_day = WorkDay.find(params[:id])

    if @work_day.update(work_day_params)
      redirect_to(
        @work_day,
        notice: "Work day actualizado correctamente."
      )
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def force_assign
    work_day = WorkDay.find(params[:id])
    location = params[:location]
    skills = params[:skills] || []

    service = ForceAssignmentService.new(
      work_day,
      location,
      skills
    )

    begin
      service.call

      redirect_to(
        work_day_path(work_day),
        notice: "#{service.guide.name} was forced into #{location}"
      )
    rescue => e
      redirect_to(
        work_day_path(work_day),
        alert: e.message
      )
    end
  end

  def preview_force_assign
    work_day = WorkDay.find(params[:id])

    skill_ids =
      Array(params[:skills])
        .reject(&:blank?)
        .map(&:to_i)

    ranker = GuideCandidateRanker.new(
      work_day: work_day,
      skill_ids: skill_ids
    )

    guide_day = ranker.next_candidate

    unless guide_day
      render json: { name: nil }
      return
    end

    guide = guide_day.guide

    # El preview utiliza exactamente la misma fuente de fairness
    # que RoleGeneratorV2 y GuideCandidateRanker.
    #
    # Esto evita mostrar un número diferente al que realmente
    # utiliza el algoritmo para ordenar los candidatos.
    snapshot =
      RollFairnessPolicy.fairness_snapshot_for(
        guide,
        before_date: work_day.date
      )

    render json: {
      name: guide.name,
      priority: snapshot[:priority],

      # Conservamos este nombre por compatibilidad con el
      # JavaScript existente.
      #
      # Internamente ahora representa las oportunidades
      # consumidas dentro del ciclo actual de fairness.
      monthly_worked_days: snapshot[:roll_worked_days]
    }
  end

  def update_availability
    @work_day = WorkDay.find(params[:id])

    ActiveRecord::Base.transaction do
      params[:availability]&.each do |guide_day_id, data|
        guide_day =
          @work_day.guide_days.find(guide_day_id)

        old_status = guide_day.status
        old_status_note = guide_day.status_note.to_s.strip

        new_status = data[:status].to_s
        new_status_note = data[:status_note].to_s.strip

        next if old_status == new_status &&
                old_status_note == new_status_note

        guide_day.update!(
          status: new_status,
          status_note: new_status_note,
          manually_modified: true
        )

        audit!(
          action: "update_availability",
          auditable: guide_day,
          work_day: @work_day,
          metadata: {
            guide_id: guide_day.guide_id,
            guide_name: guide_day.guide.name,
            before: {
              status: old_status,
              status_note: old_status_note
            },
            after: {
              status: guide_day.status,
              status_note: guide_day.status_note
            }
          }
        )
      end
    end

    redirect_to(
      @work_day,
      notice: "Availability updated."
    )
  rescue ActiveRecord::RecordInvalid => e
    redirect_to(
      @work_day,
      alert: e.record.errors.full_messages.to_sentence
    )
  end

  def update_roles
    @work_day = WorkDay.find(params[:id])

    return redirect_to(@work_day) unless params[:roles]

    @work_day
      .guide_days
      .where(id: params[:roles].keys)
      .each do |guide_day|

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

    redirect_to(
      @work_day,
      notice: "Roles updated successfully."
    )
  end

  def generate_roles
    work_day = WorkDay.find(params[:id])

    begin
      work_day.generate_roles!
      flash[:notice] = "Generated"
    rescue => e
      flash[:alert] = e.message
    end

    redirect_to work_day_path(work_day)
  end

  def publish
    unless @work_day.generated?
      redirect_to(
        @work_day,
        alert: "Only generated days can be published."
      )
      return
    end

    if @work_day.assigned_roll_count != @work_day.required_roll_count
      redirect_to(
        @work_day,
        alert: "Assignments incomplete. Assigned " \
               "#{@work_day.assigned_roll_count} of " \
               "#{@work_day.required_roll_count} required slots."
      )
      return
    end

    @work_day.publish!

    ExternalRollSender.send_work_day(@work_day)

    redirect_to(
      @work_day,
      notice: "Work day published."
    )
  end

  def unpublish
    if @work_day.published?
      @work_day.unpublish!

      redirect_to(
        @work_day,
        notice: "Work day unpublished."
      )
    else
      redirect_to(
        @work_day,
        alert: "Only published days can be unpublished."
      )
    end
  end

  def delete_with_reset
    @work_day = WorkDay.find(params[:id])

    ActiveRecord::Base.transaction do
      @work_day.work_day_versions.delete_all
      @work_day.guide_days.delete_all
      @work_day.destroy!
    end

    redirect_to(
      work_days_path,
      notice: "Work Day deleted."
    )
  end

  def reset_roll
    @work_day.reset_roll!

    redirect_to(
      @work_day,
      notice: "Roll reset. You may now set new availability."
    )
  end

  def locations
    @work_day = WorkDay.find(params[:id])

    @location_counts =
      @work_day
        .location_slots
        .group(:location)
        .count

    @passenger_counts =
      @work_day
        .location_slots
        .group(:location)
        .maximum(:passengers)
  end

  def create_slots
    @work_day = WorkDay.find(params[:id])

    @work_day.location_slots.destroy_all

    total_slots = 0

    params[:locations].each do |location, data|
      guides = data[:guides].to_i
      passengers = data[:passengers].to_i

      guides.times do
        slot =
          @work_day.location_slots.create!(
            location: location,
            passengers: passengers
          )

        default_skill = Skill.find_by(name: "ClassIII")

        if default_skill
          slot.slot_skills.create!(
            skill: default_skill
          )
        end

        total_slots += 1
      end
    end

    @work_day.update!(
      guides_requested: total_slots
    )

    redirect_to(
      @work_day,
      notice: "Slots created successfully."
    )
  end

  def edit_slots
    @work_day = WorkDay.find(params[:id])
  end

  def move_assigned_task_to_roll
  @work_day = WorkDay.find(params[:id])

  guide_day =
    @work_day.guide_days.find(
      params[:guide_day_id]
    )

  location = params[:location]

  unless guide_day.assigned_task?
    redirect_to(
      @work_day,
      alert: "Only assigned task guides can be moved to roll."
    )
    return
  end

  ActiveRecord::Base.transaction do
    slot =
      @work_day.location_slots.create!(
        location: location
      )

    default_skill = Skill.find_by(name: "ClassIII")

    slot.skills << default_skill if default_skill

    # El guía deja de estar en Assigned Task y pasa
    # oficialmente al roll normal.
    #
    # Desde este momento el GuideDay queda como :worked,
    # por lo que RollFairnessPolicy contará este día
    # como una oportunidad de roll consumida.
    guide_day.update!(
      status: :worked,
      status_note: nil,
      location: location,
      role_primary: "River Guide",
      manually_modified: true
    )

    # guides_requested debe mantenerse sincronizado
    # con la cantidad real de LocationSlots existentes.
    @work_day.update!(
      guides_requested: @work_day.location_slots.count
    )
  end

  redirect_to(
    @work_day,
    notice: "#{guide_day.guide.name} moved from Assigned Task to Roll."
  )
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
        :status_note,
        :role_primary,
        :role_secondary,
        :manually_modified
      ]
    )
  end
end