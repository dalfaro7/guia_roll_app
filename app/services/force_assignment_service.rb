class ForceAssignmentService
  attr_reader :guide

  def initialize(work_day, location, skills)
    @work_day = work_day
    @location = location

    @required_skill_ids =
      Array(skills)
        .reject(&:blank?)
        .map(&:to_i)
  end

  def call
    guide_day = next_available_guide_day

    unless guide_day
      raise "No standby guide meets the requirements"
    end

    @guide = guide_day.guide

    ActiveRecord::Base.transaction do
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
      guide_day.update!(
        status: :worked,
        location: @location,
        role_primary: "River Guide",
        manually_modified: true
      )
    end
  end

  private

  # Toda la selección del candidato se delega al ranker central.
  #
  # De esta manera ForceAssignmentService no implementa
  # ninguna regla de fairness por su cuenta.
  def next_available_guide_day
    GuideCandidateRanker.new(
      work_day: @work_day,
      skill_ids: @required_skill_ids
    ).next_candidate
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