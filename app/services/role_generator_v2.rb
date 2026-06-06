class RoleGeneratorV2

  PRIORITY_ALLOWED = {
    "Privado"   => [1,2],
    "Sara-3&4"  => [1,2,3],
    "Balsa"     => [0,1,2,3],
    "PM"        => [1,2,3]
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

  def preload_data
    @guide_days = @work_day.guide_days
                           .includes(:guide)
                           .index_by(&:guide_id)
  end

  def location_priority(location)
    case location
    when "Privado"   then 0
    when "Sara-3&4"  then 1
    when "PM"        then 2
    else                  3
    end
  end

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
    allowed = PRIORITY_ALLOWED[slot.location] || []

    candidates = GuideDay
                 .available_for_date(@work_day.date)
                 .where(work_day: @work_day)
                 .joins(guide: :skills)
                 .where(guides: { priority: allowed })
                 .where(skills: { id: required_skill_ids })
                 .group("guide_days.id, guides.id")
                 .having("COUNT(DISTINCT skills.id) = ?", required_skill_ids.size)
                 .includes(:guide)

    candidates = candidates.reject do |gd|
      @assigned_guides.include?(gd.guide_id)
    end

    selected = candidates.sort_by do |gd|
      [
        gd.guide.priority || 999,
        worked_days_for(gd.guide),
        gd.guide.name
      ]
    end.first

    selected&.guide
  end

  def assign_guide(slot, guide)
    guide_day = @guide_days[guide.id]

    guide_day.update!(
      status: :worked,
      location: slot.location,
      role_primary: "River Guide",
      role_secondary: nil
    )

    @assigned_guides << guide.id
  end

  def worked_days_for(guide)
    GuideDay.joins(:work_day)
            .where(guide: guide, status: :worked)
            .where(work_days: {
              date: @work_day.date.beginning_of_month..@work_day.date.end_of_month
            })
            .count
  end

  def diagnostic_message(slot)
    required_names = slot.skills.pluck(:name)

    guides_with_skills = Guide
                         .joins(:skills)
                         .where(skills: { id: slot.skills.pluck(:id) })
                         .group("guides.id")
                         .having("COUNT(DISTINCT skills.id) = ?", slot.skills.count)

    available = []
    unavailable = []

    guides_with_skills.each do |guide|
      gd = @guide_days[guide.id]

      if gd && gd.standby?
        available << guide.name
      else
        location = gd&.location || "none"
        status   = gd&.status || "not_in_roll"

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