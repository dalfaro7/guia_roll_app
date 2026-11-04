class WorkDaysController < ApplicationController
  before_action :set_work_day, only: [
    :show,
    :available_buses,
    :driver_payment_quote,
    :update,
    :force_assign,
    :update_availability,
    :delete_with_reset,
    :create_slots,
    :update_roles,
    :generate_roles,
    :publish,
    :unpublish,
    :reset_roll,
    :move_assigned_task_to_roll
  ]

  before_action :require_compensation_operator!, only: [
    :create, :update, :force_assign, :update_availability,
    :update_roles, :generate_roles, :publish, :unpublish,
    :delete_with_reset, :reset_roll, :create_slots,
    :move_assigned_task_to_roll
  ]
  before_action :enforce_edit_window, only: [
    :update, :force_assign, :update_availability, :update_roles,
    :generate_roles, :publish, :unpublish, :delete_with_reset,
    :reset_roll, :create_slots, :move_assigned_task_to_roll
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
    @active_drivers = Driver.active.includes(:transport_company).order(:name).to_a
    @guide_days = @work_day.guide_days.includes(:guide)
    @team_compensation_assignments = CompensationAssignment
      .where(guide_day_id: @work_day.guide_days.select(:id))
      .index_by(&:guide_day_id) if @work_day.generated?
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

  def available_buses
    response.headers["Cache-Control"] = "no-store"
    location = params[:location].presence
    candidates = location ? VehicleAvailability.for(work_day: @work_day,
      location: location) : Bus.available_on(@work_day).includes(:transport_company).order(:alias)
    buses = candidates.map do |bus|
      previous = @work_day.bus_assignments.find_by(bus_id: bus.id)
      {
        id: bus.id,
        label: "#{bus.transport_company.name} · #{bus.alias} (#{bus.capacity} pax)",
        company_id: bus.transport_company_id,
        kind: bus.vehicle_kind,
        internal_fleet: bus.transport_company.internal_fleet?,
        required_driver_id: location == "PM" ? previous&.driver_id : nil
      }
    end
    render json: { buses: buses }
  end

  def driver_payment_quote
    response.headers["Cache-Control"] = "no-store"
    bus = Bus.find_by(id: params[:bus_id])
    driver = Driver.find_by(id: params[:driver_id]) if params[:driver_id].present?
    location = params[:location].to_s
    unless bus && TransportRate::LOCATIONS.include?(location)
      return render json: { error: "Vehículo o salida inválidos" }, status: :bad_request
    end
    driver_company_ok = !driver || driver.transport_company_id.nil? ||
      driver.transport_company_id == bus.transport_company_id
    unless driver_company_ok &&
        VehicleAvailability.available?(bus: bus, work_day: @work_day,
          location: location, driver: driver, require_matching_driver: true) &&
        (!driver || DriverEligibility.available?(driver: driver, bus: bus,
          work_day: @work_day, location: location))
      return render json: { error: "Vehículo o chofer no disponible" },
        status: :unprocessable_entity
    end
    render json: Compensation::DriverPaymentQuote.call(work_day: @work_day,
      bus: bus, driver: driver, location: location)
  end

  def new
    @work_day = WorkDay.new
  end

  def create
    @work_day = WorkDay.new(work_day_params)

    if WorkDay.exists?(date: @work_day.date)
      redirect_back(
        fallback_location: work_days_path,
        alert: "Ya existe una programación para esta fecha."
      )
      return
    end

    if @work_day.save
      redirect_to(
        @work_day,
        notice: "Programación creada correctamente."
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
        notice: "Programación actualizada correctamente."
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
        notice: "#{service.guide.name} se asignó manualmente a #{location}"
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
      notice: "Disponibilidad actualizada."
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

    role_rows = @work_day.guide_days.where(id: params[:roles].keys).index_by { |day| day.id.to_s }
    ActiveRecord::Base.transaction do
      original_options = {}
      # Clear former senders before any role callback can create a photographer.
      role_rows.each do |id, guide_day|
        next unless params[:roles][id].key?(:photo_task) ||
          params[:roles][id].key?(:principal_photographer) ||
          params[:roles][id].key?(:send_photos)
        assignment = CompensationAssignment.find_by(guide_day: guide_day)
        next unless assignment
        original_options[assignment.id] = assignment.attributes.slice(
          "photo_task", "principal_photographer", "also_drives", "bus_guide"
        )
        assignment.update_columns(photo_task: "none") if assignment.photo_task != "none"
      end

      role_rows.each do |id, guide_day|
        role_data = params[:roles][id]
        updates = {}
        %w[role_primary role_secondary location].each do |field|
          updates[field] = role_data[field].presence if role_data.key?(field)
        end
        next if updates.empty? ||
          updates.all? { |field, value| guide_day.public_send(field) == value }

        before = guide_day.attributes.slice(*updates.keys)
        guide_day.update!(updates.merge(manually_modified: true, modified_by: current_user))
        audit!(action: "update_roles", auditable: guide_day, work_day: @work_day,
          metadata: { before: before, after: guide_day.attributes.slice(*updates.keys),
            reason: params[:correction_reason] })
      end

      sync_team_role_options!(role_rows, original_options)
    end

    redirect_to(
      @work_day,
      notice: "Roles actualizados correctamente."
    )
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, RuntimeError => e
    redirect_to @work_day, alert: e.message
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
        alert: "Solo se pueden publicar programaciones generadas."
      )
      return
    end

    if @work_day.assigned_roll_count != @work_day.required_roll_count
      redirect_to(
        @work_day,
        alert: "Asignaciones incompletas. Se asignaron " \
               "#{@work_day.assigned_roll_count} de " \
               "#{@work_day.required_roll_count} puestos requeridos."
      )
      return
    end

    @work_day.publish!

    ExternalRollSender.send_work_day(@work_day)
    Whatsapp::RollNotificationSender.send_work_day(@work_day)

    redirect_to(
      @work_day,
      notice: "Programación publicada correctamente."
    )
  end

  def unpublish
    if @work_day.published?
      @work_day.unpublish!

      redirect_to(
        @work_day,
        notice: "Programación reabierta correctamente."
      )
    else
      redirect_to(
        @work_day,
        alert: "Solo se puede reabrir una programación publicada."
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
      notice: "Programación eliminada correctamente."
    )
  rescue ActiveRecord::DeleteRestrictionError, ActiveRecord::RecordNotDestroyed => e
    redirect_to @work_day,
      alert: "Esta programación tiene valoración económica y no se puede eliminar. #{e.message}"
  end

  def reset_roll
    @work_day.reset_roll!

    redirect_to(
      @work_day,
      notice: "Programación reiniciada. Ya puede definir una nueva disponibilidad."
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
    submitted = params.require(:locations)
    requested = Departure::OPERATING_SECTIONS.keys.index_with do |location|
      values = submitted.require(location)
      counts = %i[guides drivers passengers].index_with do |field|
        value = Integer(values.require(field).to_s, 10)
        raise ArgumentError, "Las cantidades no pueden ser negativas." if value.negative?
        value
      end
      counts
    end

    WorkDay.transaction do
      @work_day.location_slots.destroy_all
      total_slots = 0
      default_skill = Skill.find_by(name: "ClassIII")

      requested.each do |location, counts|
        counts[:guides].times do
          slot = @work_day.location_slots.create!(
            location: location,
            passengers: counts[:passengers]
          )
          slot.slot_skills.create!(skill: default_skill) if default_skill
          total_slots += 1
        end
      end

      @work_day.update!(
        guides_requested: total_slots,
        drivers_requested_by_location: requested.transform_values { |counts| counts[:drivers] }
      )
    end

    redirect_to @work_day, notice: "Puestos creados correctamente."
  rescue ActionController::ParameterMissing, ArgumentError => e
    redirect_to locations_work_day_path(@work_day),
      alert: "Revise las cantidades de guías, choferes y pasajeros: #{e.message}"
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
      alert: "Solo los guías con tarea asignada pueden moverse a la programación."
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
    notice: "#{guide_day.guide.name} fue movido de Tarea Asignada a la programación."
  )
end

  private

  def sync_team_role_options!(role_rows, original_options)
    rows = role_rows.filter_map do |id, guide_day|
      data = params[:roles][id]
      next unless data.key?(:photo_task) || data.key?(:principal_photographer) ||
        data.key?(:send_photos)
      assignment = CompensationAssignment.find_by(guide_day: guide_day)
      next unless assignment

      photo_task = data[:photo_task].presence || "none"
      raise "Tarea de fotos inválida" unless CompensationAssignment::PHOTO_TASKS.include?(photo_task)
      sends_photos = ActiveModel::Type::Boolean.new.cast(data[:send_photos])
      raise "Elija una sola función de fotos para este guía" if sends_photos && photo_task != "none"
      photo_task = "send_only" if sends_photos
      if photo_task != "none" && (assignment.role_code == "photographer" ||
          assignment.role_code.start_with?("tl_", "hg_"))
        raise "Esta función no admite una tarea adicional de fotos"
      end
      selected = ActiveModel::Type::Boolean.new.cast(data[:principal_photographer])
      raise "El responsable principal debe ser fotógrafo" if selected && assignment.role_code != "photographer"
      { assignment: assignment, photo_task: photo_task, selected: selected }
    end
    return if rows.empty?

    departures = rows.map { |row| row[:assignment].departure }.uniq
    chosen = {}
    departures.each do |departure|
      photographers = departure.compensation_assignments.active.where(role_code: "photographer").to_a
      submitted = rows.select { |row| row[:assignment].departure_id == departure.id &&
        row[:assignment].role_code == "photographer" }
      selected = submitted.select { |row| row[:selected] }
      raise "Seleccione un solo fotógrafo principal para #{departure.label}" if selected.size > 1
      external_principal = photographers.find do |photographer|
        photographer.principal_photographer? &&
          submitted.none? { |row| row[:assignment].id == photographer.id }
      end
      if photographers.size > 1 && submitted.any? && selected.empty? &&
          external_principal.nil?
        raise "Seleccione un fotógrafo principal para #{departure.label}"
      end
      chosen[departure.id] = selected.first&.dig(:assignment) ||
        external_principal ||
        (photographers.one? ? photographers.first : photographers.find(&:principal_photographer?))
    end

    # Move the principal in one transaction, including an existing manual
    # assignment that is not shown in the team table.
    departures.each do |departure|
      principal = chosen[departure.id]
      next unless principal
      departure.compensation_assignments.active.where(principal_photographer: true)
        .where.not(id: principal.id).each do |previous|
          previous.update_columns(principal_photographer: false,
            updated_by_id: current_user.id, updated_at: Time.current)
          audit!(action: "transfer_principal_photographer", auditable: previous,
            work_day: @work_day, metadata: { new_principal_assignment_id: principal.id })
        end
      unless principal.principal_photographer?
        principal.update_columns(principal_photographer: true,
          updated_by_id: current_user.id, updated_at: Time.current)
        audit!(action: "assign_principal_photographer", auditable: principal,
          work_day: @work_day, metadata: { departure_id: departure.id })
      end
    end

    rows.each do |row|
      assignment = row[:assignment]
      role = assignment.role_code
      secondary = assignment.guide_day.role_secondary.to_s
      head_role = role.start_with?("tl_", "hg_")
      changes = {
        photo_task: role == "photographer" || head_role ? "none" : row[:photo_task],
        principal_photographer: assignment.id == chosen[assignment.departure_id]&.id,
        also_drives: !head_role && secondary == "Driver",
        bus_guide: !head_role && secondary.include?("Bus Guide")
      }
      before = original_options[assignment.id] || assignment.attributes.slice(*changes.keys)
      changed = before.stringify_keys != changes.stringify_keys
      assignment.update!(changes.merge(updated_by: current_user,
        source: changed ? "manual" : assignment.source))
      if changed
        audit!(action: "update_compensation_from_team_roles", auditable: assignment,
          work_day: @work_day, metadata: { before: before,
            after: assignment.attributes.slice(*changes.keys) })
      end
    end
    departures.each do |departure|
      departure.compensation_assignments.active.each { |assignment| raise ActiveRecord::RecordInvalid, assignment unless assignment.valid? }
    end
    Compensation::RepriceDay.call(@work_day)
  end

  def enforce_edit_window
    allowed = Compensation::EditWindow.allowed?(
      user: current_user, work_day: @work_day
    )
    closed = Compensation::EditWindow.closed?(@work_day)
    return if allowed && (!closed || !current_user.admin? ||
      params[:correction_reason].present?)

    redirect_to @work_day,
      alert: allowed ? "Indique el motivo de la corrección." :
        "Esta programación ya cerró. Solo un administrador puede corregirla."
  end

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