class WorkDayDistribution
  SECTION_COLORS = {
    "Balsa" => "location-balsa",
    "Sara-3&4" => "location-sara",
    "PM" => "location-pm",
    "Privado" => "location-privado"
  }.freeze

  def initialize(work_day)
    @work_day = work_day
    @guide_days = work_day.guide_days.includes(:guide).to_a
    @bus_assignments = work_day.bus_assignments.includes(:driver, :bus).to_a
    @assignments = CompensationAssignment.joins(:departure)
      .where(departures: { work_day_id: work_day.id }, status: %w[planned performed])
      .where.not(departures: { status: "canceled" })
      .includes(:guide, :driver, :departure).to_a
    @manual_days = ManualDayOff.where(date: work_day.date).includes(:guide).to_a
  end

  def operating_sections
    sections = Departure::OPERATING_SECTIONS.map do |label, locations|
      { label: label, rows: rows_for(locations, label) }
    end
    known_locations = Departure::OPERATING_SECTIONS.values.flatten
    other_locations = (@guide_days.select(&:worked?).map(&:location) +
      @bus_assignments.map(&:location) +
      @assignments.map { |assignment| assignment.departure.location }).compact.uniq - known_locations
    sections << { label: "Otros lugares", rows: rows_for(other_locations, "Otros lugares") } if other_locations.any?
    sections
  end

  def availability_sections
    manual_by_guide = @manual_days.index_by(&:guide_id)
    operating_guide_ids = @guide_days.select(&:worked?).map(&:guide_id) +
      @assignments.filter_map(&:guide_id)
    active_guide_days = @guide_days.reject do |day|
      day.worked? || operating_guide_ids.include?(day.guide_id)
    end
    tasks = active_guide_days.select(&:assigned_task?)
    standby = if @work_day.published?
      @work_day.standby_guides_for_published_roll.reject do |day|
        operating_guide_ids.include?(day.guide_id)
      end
    else
      active_guide_days.select(&:standby?)
    end.reject { |day| manual_by_guide.key?(day.guide_id) }
    free = active_guide_days.select { |day| day.day_off? || day.vacation? }
    manual = @manual_days.reject do |day|
      @guide_days.any? { |guide_day| guide_day.guide_id == day.guide_id &&
        !guide_day.standby? }
    end
    penalized = active_guide_days.select(&:penalized?)

    [
      { label: "Tarea asignada", rows: sorted_days(tasks).map { |day| availability_row(day, "Tarea asignada") } },
      { label: "En espera", rows: standby.map { |day| availability_row(day, "En espera") } },
      { label: "Libres", rows: sorted_days(free).map { |day| availability_row(day, day.vacation? ? "Vacaciones" : "Libre") } +
        manual.sort_by { |day| [day.guide.priority, day.guide.name] }.map { |day| {
          name: day.guide.name, status: "Libre manual", kind: :guide
        } } },
      { label: "Penalizados", rows: sorted_days(penalized).map { |day| availability_row(day, "Penalizado") } }
    ]
  end

  private

  def rows_for(locations, label)
    guide_days = @guide_days.select { |day| day.worked? && locations.include?(day.location) }
      .sort_by { |day| [special_role_order(day, label), day.guide.priority, day.guide.name] }
    guide_rows = guide_days.map do |day|
      { name: day.guide.name, location: day.location, primary: day.role_primary,
        secondary: day.role_secondary, status: "Trabaja", kind: :guide,
        color: SECTION_COLORS[label] }
    end

    extra_guide_rows = @assignments.select do |assignment|
      assignment.guide_id.present? && assignment.guide_day_id.nil? &&
        locations.include?(assignment.departure.location)
    end.sort_by { |assignment| [assignment.departure.starts_at, assignment.guide.name] }
      .map do |assignment|
        primary, secondary = assignment_roles(assignment)
        { name: assignment.guide.name, location: assignment.departure.location,
          primary: primary, secondary: secondary, status: "Trabaja",
          note: assignment.departure.label, kind: :guide, color: SECTION_COLORS[label] }
      end

    bus_rows = @bus_assignments.select do |assignment|
      assignment.driver_id.present? && locations.include?(assignment.location)
    end.sort_by { |assignment| [assignment.driver.name, assignment.bus.alias] }
      .map do |assignment|
        { name: assignment.driver.name, location: assignment.location,
          primary: "Driver", status: "Asignado", note: assignment.bus.alias,
          kind: :driver, color: SECTION_COLORS[label] }
      end
    bus_driver_locations = @bus_assignments.filter_map do |assignment|
      [assignment.driver_id, assignment.location] if assignment.driver_id.present?
    end
    other_driver_rows = @assignments.select do |assignment|
      assignment.driver_id.present? && locations.include?(assignment.departure.location) &&
        !bus_driver_locations.include?([assignment.driver_id, assignment.departure.location])
    end.sort_by { |assignment| [assignment.departure.starts_at, assignment.driver.name] }
      .map do |assignment|
        { name: assignment.driver.name, location: assignment.departure.location,
          primary: "Driver", status: "Asignado", note: assignment.departure.label,
          kind: :driver, color: SECTION_COLORS[label] }
      end
    guide_rows + extra_guide_rows + bus_rows + other_driver_rows
  end

  def special_role_order(day, label)
    return 0 if label == "Sara-3&4"

    ["Photographer", "Safety Kayaker"].include?(day.role_primary) ? 1 : 0
  end

  def assignment_roles(assignment)
    case assignment.role_code
    when "photographer" then ["Photographer", nil]
    when "safety_kayak" then ["Safety Kayaker", nil]
    when /\Atl_/ then ["River Guide", "Tour Leader"]
    when /\Ahg_/ then ["River Guide", "Head Guide"]
    else
      extras = []
      extras << "Guía de bus" if assignment.bus_guide?
      extras << "Envío de fotos" if assignment.photo_task == "send_only"
      extras << "Toma y envía fotos" if assignment.photo_task == "take_and_send"
      extras << "Chofer" if assignment.also_drives?
      ["River Guide", extras.join(" · ").presence]
    end
  end

  def sorted_days(days)
    days.sort_by { |day| [day.guide.priority, day.guide.name] }
  end

  def availability_row(day, status)
    { name: day.guide.name, status: status, note: day.status_note, kind: :guide }
  end
end
