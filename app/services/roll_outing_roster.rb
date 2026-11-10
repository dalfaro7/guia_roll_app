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

  def coverage_errors
    required = @work_day.location_slots.pluck(:location)
      .map { |location| section_for(location) }.tally
    actual = counts_by_section

    (required.keys | actual.keys).filter_map do |section|
      expected = required.fetch(section, 0)
      assigned = actual.fetch(section, 0)
      next if expected == assigned

      "#{section}: #{assigned} de #{expected} puestos cubiertos"
    end
  end

  private

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
