class RoleGeneratorV2
  def initialize(work_day)
    @work_day = work_day
    @month    = work_day.date.beginning_of_month
    @assigned_guides = []

    preload_data
    compute_skill_rarity
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

  # =====================================
  # PRELOAD
  # =====================================
  def preload_data
    @guide_days = @work_day.guide_days.includes(:guide).index_by(&:guide_id)
    @balances   = MonthlyBalance.where(month: @month).index_by(&:guide_id)
  end

  # =====================================
  # RAREZA DE SKILLS
  # =====================================
  def compute_skill_rarity
    counts = Hash.new(0)
    Guide.active.joins(:skills).pluck("skills.id").each { |sid| counts[sid] += 1 }
    @skill_rarity = counts
  end

  # =====================================
  # PRIORIDAD LOCATION
  # =====================================
  def location_priority(location)
    case location
    when "Privado"   then 0
    when "Sara-3&4"  then 1
    else                  2
    end
  end

  # =====================================
  # ORDEN DE SLOTS
  # =====================================
  def ordered_slots
  @work_day.location_slots
           .includes(:skills)
           .to_a
           .sort_by do |slot|

    rarity_score = slot.skills.sum { |s| @skill_rarity[s.id] || 0 }

    [
      location_priority(slot.location),
      rarity_score,
      -slot.skills.count
    ]

  end
end

  # =====================================
  # SELECCIÓN DE GUÍA
  # =====================================
  def select_guide_for_slot(slot)

  required_skill_ids = slot.skills.map(&:id)

  candidates = @work_day.guide_days
                        .includes(guide: :skills)
                        .joins(:guide)
                        .where(status: :standby)
                        .reject { |gd| @assigned_guides.include?(gd.guide_id) }

  candidates = candidates.select do |gd|

    guide = gd.guide

    # prioridad 0 no puede entrar a Sara ni Privado
    if guide.priority == 0 && ["Sara-3&4", "Privado"].include?(slot.location)
      next false
    end

    guide_skill_ids = guide.skills.map(&:id)

    (required_skill_ids - guide_skill_ids).empty?

  end

  selected = candidates.sort_by do |gd|

    guide = gd.guide

    [
      guide.priority || 999,
      worked_days_for(guide)
    ]

  end.first

  selected&.guide

end

  # =====================================
  # ASIGNAR GUÍA
  # =====================================
  def assign_guide(slot, guide)

    guide_day = @guide_days[guide.id]

    guide_day.update!(
      status: :worked,
      location: slot.location,
      role_primary: "River Guide",
      role_secondary: nil
    )

    increment_balance(guide)

    @assigned_guides << guide.id
  end

  # =====================================
  # EQUIDAD
  # =====================================
  def worked_days_for(guide)
    @balances[guide.id]&.worked_days.to_i
  end

  def increment_balance(guide)

    balance = @balances[guide.id]

    unless balance
      balance = MonthlyBalance.create!(
        guide: guide,
        month: @month,
        worked_days: 0
      )
      @balances[guide.id] = balance
    end

    balance.update!(
      worked_days: balance.worked_days + 1
    )
  end

  # =====================================
  # DIAGNÓSTICO
  # =====================================
  def diagnostic_message(slot)

    required_names = slot.skills.pluck(:name)

    guides_with_skills = Guide.active
      .joins(:skills)
      .where(skills: { id: slot.skills.pluck(:id) })
      .group("guides.id")
      .having("COUNT(DISTINCT skills.id) = ?", slot.skills.count)

    available = []
    unavailable = []

    guides_with_skills.each do |guide|

      gd = @guide_days[guide.id]

      if gd && !gd.day_off? && !gd.vacation?
        available << guide.name
      else
        unavailable << "#{guide.name} (#{gd&.status})"
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