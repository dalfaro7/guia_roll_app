class ForceAssignmentService
  attr_reader :guide, :guide_day

  def initialize(work_day, location, skills, guide_id: nil, actor: nil)
    @work_day = work_day
    @location = location
    @guide_id = guide_id.presence
    @actor = actor

    @required_skill_ids =
      Array(skills)
        .reject(&:blank?)
        .map(&:to_i)
  end

  def call
    @work_day.with_lock do
      raise "La programación debe estar generada." unless @work_day.generated?
      @guide_day = next_available_guide_day
      raise "No hay un guía disponible que cumpla los requisitos." unless @guide_day

      @guide = @guide_day.guide
      slot = create_location_slot

      assign_skills_to_slot(slot)

      # El guides_requested debe reflejar la cantidad real
      # de slots existentes después de la asignación forzada.
      @work_day.update!(
        guides_requested: @work_day.location_slots.count
      )

      # Al entrar al roll, el guía pasa realmente a worked.
      # Por lo tanto, este día consumirá una oportunidad
      # dentro del fairness del ciclo actual.
      @guide_day.update!(
        status: :worked,
        location: @location,
        role_primary: "River Guide",
        manually_modified: true,
        modified_by: @actor
      )
    end
  end

  private

  # Toda la selección del candidato se delega al ranker central.
  #
  # De esta manera ForceAssignmentService no implementa
  # ninguna regla de fairness por su cuenta.
  def next_available_guide_day
    return selected_guide_day if @guide_id

    GuideCandidateRanker.new(
      work_day: @work_day,
      skill_ids: @required_skill_ids
    ).next_candidate
  end

  def selected_guide_day
    raise "La selección de un guía específico solo está disponible para Balsa." unless @location == "Balsa"

    guide = Guide.active.includes(:skills).find(@guide_id)
    unless RoleGeneratorV2::PRIORITY_ALLOWED.fetch("Balsa").include?(guide.priority)
      raise "El nivel de este guía no está habilitado para Balsa."
    end
    if ManualDayOff.exists?(guide_id: guide.id, date: @work_day.date)
      raise "El guía tiene un día libre registrado para esta fecha."
    end
    if CompensationAssignment.active.joins(:departure)
        .where(guide_id: guide.id, departures: { work_day_id: @work_day.id }).exists?
      raise "El guía ya tiene una salida asignada en esta programación."
    end
    class_iii = Skill.find_by(name: "ClassIII")
    unless class_iii && guide.skills.include?(class_iii) &&
        (@required_skill_ids - guide.skills.map(&:id)).empty?
      raise "El guía no cumple las habilidades requeridas para Balsa."
    end

    day = @work_day.guide_days.find_or_initialize_by(guide: guide)
    unless day.new_record? || day.standby?
      raise "El guía ya tiene otro estado o asignación en esta programación."
    end
    day.status = :standby if day.new_record?
    day.save! if day.new_record?
    day
  end

  def create_location_slot
    LocationSlot.create!(
      work_day: @work_day,
      location: @location
    )
  end

  def assign_skills_to_slot(slot)
    return if @required_skill_ids.empty?

    slot.skills = Skill.where(
      id: @required_skill_ids
    )
  end
end
