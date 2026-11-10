# Presenta una fila por salida real, incluso cuando un guía realiza dos
# salidas el mismo día. Los GuideDay antiguos siguen funcionando sin una
# asignación económica vinculada.
class RollOutingRoster
  Entry = Struct.new(:guide, :location, :role_primary, :role_secondary,
    keyword_init: true) do
    def location_css_class
      case location
      when "Sara-3&4", "Sara-3", "Sara-4" then "location-sara"
      when "Balsa" then "location-balsa"
      when "PM" then "location-pm"
      when "Privado" then "location-privado"
      else ""
      end
    end
  end

  def initialize(work_day)
    @work_day = work_day
  end

  def entries
    @entries ||= begin
      assignments = CompensationAssignment.joins(:departure)
        .where(departures: { work_day_id: @work_day.id })
        .where.not(guide_id: nil)
        .includes(:guide, :departure).to_a
      # Una cancelación económica aislada no borra el trabajo que todavía
      # consta en GuideDay. Una salida completa cancelada sí se excluye.
      represented = assignments.select do |assignment|
        assignment.departure.status == "canceled" ||
          %w[planned performed].include?(assignment.status)
      end
      represented_days = represented.filter_map(&:guide_day_id)
      represented_locations = represented.map do |assignment|
        [assignment.guide_id, section_for(assignment.departure.location)]
      end

      current = assignments.filter_map do |assignment|
        next unless %w[planned performed].include?(assignment.status)
        next if assignment.departure.status == "canceled"

        primary, secondary = assignment_roles(assignment)
        Entry.new(guide: assignment.guide, location: assignment.departure.location,
          role_primary: primary, role_secondary: secondary)
      end

      legacy = @work_day.guide_days.worked.includes(:guide).filter_map do |day|
        next if represented_days.include?(day.id)
        next if represented_locations.include?([day.guide_id, section_for(day.location)])

        Entry.new(guide: day.guide, location: day.location,
          role_primary: day.role_primary, role_secondary: day.role_secondary)
      end

      current + legacy
    end
  end

  def counts_by_section
    entries.map { |entry| section_for(entry.location) }.tally
  end

  # Puestos de Sara/PM que todavía no tienen una persona con las
  # habilidades requeridas. Si ya hay tantas asignaciones como puestos,
  # corresponde corregir una asignación existente en vez de agregar otra.
  def unfilled_sara_pm_slots
    slots = @work_day.location_slots.includes(:skills).to_a
    %w[Sara-3&4 PM].flat_map do |section|
      section_slots = slots.select { |slot| section_for(slot.location) == section }
      section_entries = entries.select { |entry| section_for(entry.location) == section }
      next [] if section_entries.size >= section_slots.size

      matched = slot_matches(section_slots, section_entries)
      section_slots.each_with_index.filter_map do |slot, index|
        slot unless matched.key?(index)
      end
    end
  end

  def coverage_errors
    slots = @work_day.location_slots.includes(:skills).to_a
    required = slots.map { |slot| section_for(slot.location) }.tally
    actual = counts_by_section

    (required.keys | actual.keys).filter_map do |section|
      expected = required.fetch(section, 0)
      assigned = actual.fetch(section, 0)
      if assigned < expected
        missing = expected - assigned
        "#{section}: #{missing == 1 ? 'falta 1 puesto' : "faltan #{missing} puestos"} por cubrir"
      elsif assigned > expected
        extra = assigned - expected
        "#{section}: #{extra == 1 ? 'sobra 1 asignación' : "sobran #{extra} asignaciones"}"
      elsif %w[Sara-3&4 PM].include?(section) && expected.positive? &&
          !skills_cover_slots?(slots.select { |slot| section_for(slot.location) == section },
            entries.select { |entry| section_for(entry.location) == section })
        "#{section}: hay puestos cuyos requisitos de habilidades no están cubiertos"
      end
    end
  end

  private

  def skills_cover_slots?(slots, assigned_entries)
    slot_matches(slots, assigned_entries).size == slots.size
  end

  def slot_matches(slots, assigned_entries)
    guides = assigned_entries.map(&:guide).uniq
    ActiveRecord::Associations::Preloader.new(
      records: guides, associations: :skills
    ).call
    requirements = slots.map { |slot| slot.skills.map(&:id) }
    guide_skills = assigned_entries.map { |entry| entry.guide.skills.map(&:id) }
    slot_owners = {}

    assigned_entries.each_index do |entry_index|
      match_entry_to_slot(entry_index, requirements, guide_skills, slot_owners, [])
    end
    slot_owners
  end

  def match_entry_to_slot(entry_index, requirements, guide_skills, slot_owners, seen)
    requirements.each_with_index do |required, slot_index|
      next if seen.include?(slot_index)
      next unless (required - guide_skills[entry_index]).empty?

      seen << slot_index
      owner = slot_owners[slot_index]
      if owner.nil? ||
          match_entry_to_slot(owner, requirements, guide_skills, slot_owners, seen)
        slot_owners[slot_index] = entry_index
        return true
      end
    end
    false
  end

  def section_for(location)
    Departure::OPERATING_SECTIONS.find do |_section, locations|
      locations.include?(location)
    end&.first || location.presence || "Sin ubicación"
  end

  def assignment_roles(assignment)
    case assignment.role_code
    when "photographer" then ["Photographer", nil]
    when "safety_kayak" then ["Safety Kayaker", nil]
    when /\Atl_/ then ["River Guide", "Tour Leader"]
    when /\Ahg_/ then ["River Guide", "Head Guide"]
    else
      extras = []
      extras << "Bus Guide & Towels" if assignment.bus_guide?
      extras << "SendPhotos" if assignment.photo_task == "send_only"
      extras << "Take and Send Photos" if assignment.photo_task == "take_and_send"
      extras << "Driver" if assignment.also_drives?
      ["River Guide", extras.join(" · ").presence]
    end
  end
end
