class RoleGeneratorV2
  PRIORITY_ALLOWED = {
    "Privado"  => [1, 2],
    "Sara-3&4" => [1, 2, 3, 5],
    "Balsa"    => [0, 1, 2, 3, 4],
    "PM"       => [1, 2, 3, 5]
  }

  def initialize(work_day)
    @work_day = work_day
    @assigned_guides = []

    preload_data
  end

  def generate!
    raise "WorkDay must be draft" unless @work_day.draft?

    ActiveRecord::Base.transaction do
      ordered_slots.each do |slot|
        guide = select_guide_for_slot(slot)

        raise diagnostic_message(slot) unless guide

        assign_guide(slot, guide)
      end

      @work_day.update!(status: :generated)
    end
  end

  private

  # Precarga los GuideDay del WorkDay actual para evitar búsquedas
  # repetidas durante la asignación.
  def preload_data
    @guide_days = @work_day.guide_days
                           .includes(:guide)
                           .index_by(&:guide_id)
  end

  # Define el orden en que se procesan las diferentes ubicaciones.
  # Los slots más sensibles se asignan primero.
  def location_priority(location)
    case location
    when "Privado"  then 0
    when "Sara-3&4" then 1
    when "PM"       then 2
    else                 3
    end
  end

  # Ordena primero por ubicación y luego por cantidad de skills requeridos.
  #
  # Un slot con más requisitos se procesa antes para evitar consumir
  # prematuramente un guía que podría ser necesario en ese slot.
  def ordered_slots
    @work_day.location_slots
             .includes(:skills)
             .to_a
             .sort_by do |slot|
      [
        location_priority(slot.location),
        -slot.skills.count
      ]
    end
  end

  def select_guide_for_slot(slot)
    required_skill_ids = slot.skills.map(&:id)
    allowed_priorities = PRIORITY_ALLOWED[slot.location] || []

    candidates =
      GuideDay
        .available_for_date(@work_day.date)
        .where(work_day: @work_day)
        .joins(guide: :skills)
        .where(guides: { priority: allowed_priorities })
        .where(skills: { id: required_skill_ids })
        .group("guide_days.id, guides.id")
        .having(
          "COUNT(DISTINCT skills.id) = ?",
          required_skill_ids.size
        )
        .includes(:guide)
        .to_a
    ActiveRecord::Associations::Preloader.new(
      records: candidates.map(&:guide), associations: :skills
    ).call

    # La generación automática conserva una sola salida por guía.
    # La segunda salida en PM se asignará desde la operación en otro paso.
    candidates = candidates.reject do |guide_day|
      @assigned_guides.include?(guide_day.guide_id)
    end

    candidates = candidates.filter_map do |guide_day|
      tier = candidate_tier_for(slot, guide_day.guide)
      [tier, guide_day] if tier
    end

    # Dentro de cada grupo se conserva exactamente el ranking de fairness.
    selected = candidates.min_by do |tier, guide_day|
      [tier, *RollFairnessPolicy.ranking_key_for(
        guide_day.guide, before_date: @work_day.date
      )]
    end

    selected&.last&.guide
  end

  def candidate_tier_for(slot, guide)
    return 0 unless %w[Sara-3&4 PM].include?(slot.location)

    # El puesto con Busguide/Computer u otros requisitos puede cubrirlo
    # un guía calificado del grupo habitual sin Roll de Sara.
    specialized = slot.skills.any? { |skill| skill.name != "ClassIV" }
    return 0 if specialized && [1, 2, 3].include?(guide.priority)
    return 0 if !specialized && guide.priority == 1

    # Los puestos generales corresponden al nuevo grupo de Sara.
    return 1 if guide.priority == 5 &&
      guide.skills.any? { |skill| skill.name == "Roll de Sara" }

    nil
  end

  def assign_guide(slot, guide)
    guide_day = @guide_days[guide.id]

    guide_day.update!(
      status: :worked,
      location: slot.location,
      role_primary: "River Guide",
      role_secondary: nil
    )

    # Evita que el mismo guía vuelva a ser seleccionado
    # para otro slot durante esta generación.
    @assigned_guides << guide.id
  end

  def diagnostic_message(slot)
    required_skill_ids = slot.skills.pluck(:id)
    required_names = slot.skills.pluck(:name)

    guides_with_skills =
      Guide
        .joins(:skills)
        .where(skills: { id: required_skill_ids })
        .group("guides.id")
        .having(
          "COUNT(DISTINCT skills.id) = ?",
          required_skill_ids.size
        )

    available = []
    unavailable = []

    guides_with_skills.each do |guide|
      guide_day = @guide_days[guide.id]

      if guide_day&.standby?
        available << guide.name
      else
        location = guide_day&.location || "none"
        status = guide_day&.status || "not_in_roll"

        unavailable << "#{guide.name} (#{status} at #{location})"
      end
    end

    [
      "No available guide for #{slot.location}",
      "",
      "Required skills:",
      required_names.join(", "),
      "",
      "Guides matching skills:",
      (guides_with_skills.map(&:name).presence || ["none"]).join(", "),
      "",
      "Available:",
      (available.presence || ["none"]).join(", "),
      "",
      "Unavailable:",
      (unavailable.presence || ["none"]).join(", ")
    ].join("\n")
  end
end