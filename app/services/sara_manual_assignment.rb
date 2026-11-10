# Completa un puesto ya solicitado de Sara o PM. La segunda salida en PM
# queda como otra CompensationAssignment, sin mover el GuideDay de Sara.
class SaraManualAssignment
  class InvalidSelection < StandardError; end
  Candidate = Struct.new(:guide, :kind, :label, keyword_init: true)

  def initialize(work_day)
    @work_day = work_day
  end

  def unfilled_slots
    RollOutingRoster.new(@work_day).unfilled_sara_pm_slots
  end

  def candidates_for(slot)
    return [] unless %w[Sara-3&4 PM].include?(slot.location)

    required = slot.skills.map(&:id)
    specialized = slot.skills.any? { |skill| skill.name != "ClassIV" }
    days = @work_day.guide_days.index_by(&:guide_id)
    occupied = RollOutingRoster.new(@work_day).entries.group_by { |entry| entry.guide.id }
    manual_days_off = ManualDayOff.where(date: @work_day.date).pluck(:guide_id)

    Guide.where(priority: [1, 2, 3, 5, 6]).includes(:skills).filter_map do |guide|
      next if guide.pay_category.blank? || manual_days_off.include?(guide.id)
      next unless (required - guide.skills.map(&:id)).empty?

      day = days[guide.id]
      assignments = occupied.fetch(guide.id, [])
      kind = if guide.priority == 6 &&
          guide.skills.any? { |skill| skill.name == "address_Sarapiqui" } &&
          guide.skills.any? { |skill| skill.name == "ClassIV" } &&
          (day.nil? || day.standby?) && assignments.empty?
        :reserve
      elsif guide.active? && (day.nil? || day.standby?) && assignments.empty?
        if guide.priority == 5 &&
            guide.skills.any? { |skill| skill.name == "Roll de Sara" }
          :standby_sara
        elsif specialized && [1, 2, 3].include?(guide.priority)
          :standby_specialist
        end
      elsif slot.location == "PM" && guide.active? && guide.priority == 5 &&
          day&.worked? && %w[Sara-3&4 Sara-3 Sara-4].include?(day.location) &&
          assignments.one? && assignments.first.location.to_s.start_with?("Sara")
        :second_outing
      end
      next unless kind

      label = case kind
      when :reserve then "#{guide.name} · reserva prioridad 6"
      when :second_outing then "#{guide.name} · segunda salida Sara → PM"
      when :standby_specialist then "#{guide.name} · especialista en espera"
      else "#{guide.name} · Roll de Sara en espera"
      end
      Candidate.new(guide: guide, kind: kind, label: label)
    end.sort_by do |candidate|
      kind_order = { standby_specialist: 0, standby_sara: 1,
        reserve: 2, second_outing: 3 }.fetch(candidate.kind)
      ranking = candidate.kind == :reserve ? candidate.guide.name :
        ranking_key_for(candidate.guide)
      [kind_order, ranking]
    end
  end

  def call(slot_id:, guide_id:, actor:)
    @work_day.with_lock do
      raise InvalidSelection, "La programación debe estar generada." unless @work_day.generated?

      slot = @work_day.location_slots.includes(:skills).find(slot_id)
      ensure_departure_open!(slot.location)
      unless unfilled_slots.any? { |available| available.id == slot.id }
        raise InvalidSelection, "Ese puesto ya está cubierto o no pertenece a Sara/PM."
      end
      candidate = candidates_for(slot).find { |entry| entry.guide.id == guide_id.to_i }
      raise InvalidSelection, "El guía ya no está disponible para ese puesto." unless candidate

      assign_candidate(slot, candidate, actor)
    end
    @guide
  end

  def extra_bus_candidates_for(location)
    return [] unless %w[Sara-3&4 PM].include?(location)

    skills = Skill.where(name: %w[ClassIV Busguide]).to_a
    return [] unless skills.size == 2

    virtual_slot = LocationSlot.new(work_day: @work_day, location: location)
    virtual_slot.skills = skills
    candidates_for(virtual_slot)
  end

  def add_bus_guide(location:, guide_id:, actor:)
    @work_day.with_lock do
      raise InvalidSelection, "La programación debe estar generada." unless @work_day.generated?
      unless %w[Sara-3&4 PM].include?(location)
        raise InvalidSelection, "Solo puede añadir guías de bus a Sara o PM."
      end
      ensure_departure_open!(location)
      skills = Skill.where(name: %w[ClassIV Busguide]).to_a
      raise InvalidSelection, "Faltan las habilidades Clase IV o Guía de bus." unless skills.size == 2

      slot = @work_day.location_slots.create!(location: location)
      slot.skills = skills
      candidate = candidates_for(slot).find { |entry| entry.guide.id == guide_id.to_i }
      raise InvalidSelection, "El guía ya no está disponible para ese puesto." unless candidate

      assign_candidate(slot, candidate, actor)
      @work_day.update!(guides_requested: @work_day.location_slots.count)
    end
    @guide
  end

  private

  def ranking_key_for(guide)
    @ranking_keys ||= {}
    @ranking_keys[guide.id] ||= RollFairnessPolicy.ranking_key_for(
      guide, before_date: @work_day.date
    )
  end

  def ensure_departure_open!(location)
    departure = @work_day.departures.find_by(label: location)
    if departure&.status == "canceled"
      raise InvalidSelection, "No se puede asignar un guía a una salida cancelada."
    end
  end

  def assign_candidate(slot, candidate, actor)
    @guide = candidate.guide
    if candidate.kind == :second_outing
      add_second_outing(slot, actor)
    else
      fill_first_outing(slot, actor)
    end
  end

  def bus_guide_slot?(slot)
    slot.skills.any? { |skill| skill.name == "Busguide" }
  end

  def fill_first_outing(slot, actor)
    day = @work_day.guide_days.find_by(guide: @guide)
    attributes = { status: :worked, location: slot.location,
      role_primary: "River Guide",
      role_secondary: bus_guide_slot?(slot) ? "Bus Guide & Towels" : nil,
      manually_modified: true, modified_by: actor }
    if day
      day.update!(attributes)
    else
      day = @work_day.guide_days.create!(attributes.merge(guide: @guide))
    end
    ensure_priced!(CompensationAssignment.find_by(guide_day: day))
    AuditLog.create!(user: actor, action: "assign_sara_guide",
      auditable_type: "GuideDay", auditable_id: day.id, work_day: @work_day,
      metadata: { guide_id: @guide.id, location_slot_id: slot.id,
        location: slot.location, mode: "first_outing" })
  end

  def ensure_priced!(assignment)
    return unless Compensation::EditWindow.applicable?(@work_day)
    return if assignment && %w[planned performed].include?(assignment.status) &&
      assignment.pricing_error.blank? && assignment.priced_at.present?

    raise InvalidSelection,
      assignment&.pricing_error.presence ||
      "La asignación económica está cancelada o no tiene pago calculado."
  end

  def add_second_outing(slot, actor)
    departure = @work_day.departures.find_or_create_by!(label: "PM") do |outing|
      outing.location = "PM"
      outing.starts_at = Departure.fixed_start_for(@work_day.date, "PM")
    end
    assignment = departure.compensation_assignments.create!(
      guide: @guide, role_code: "river_guide", source: "manual",
      bus_guide: bus_guide_slot?(slot),
      status: departure.closed? ? "performed" : "planned", updated_by: actor
    )
    Compensation::RepriceDay.call(@work_day, guide: @guide)
    ensure_priced!(assignment.reload)
    AuditLog.create!(user: actor, action: "assign_sara_second_outing",
      auditable_type: "CompensationAssignment", auditable_id: assignment.id,
      work_day: @work_day,
      metadata: { guide_id: @guide.id, location_slot_id: slot.id,
        location: slot.location, mode: "second_outing" })
  end
end
