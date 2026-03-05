class ForceAssignmentService

  attr_reader :guide

  def initialize(work_day, location, skills)
    @work_day = work_day
    @location = location
    @required_skill_ids = skills.map(&:to_i)
    @month = work_day.date.beginning_of_month
  end

  def call

    guide_day = next_available_guide_day
    raise "No standby guide meets the requirements" unless guide_day

    @guide = guide_day.guide

    ActiveRecord::Base.transaction do

      slot = LocationSlot.create!(
        work_day: @work_day,
        location: @location
      )

      assign_skills_to_slot(slot)

      guide_day.update!(
        status: :worked,
        location: @location,
        role_primary: "River Guide"
      )

      increment_balance(@guide)

    end

  end

  private

  def next_available_guide_day

    candidates = @work_day.guide_days
                          .includes(guide: :skills)
                          .joins(:guide)
                          .where(status: :standby)
                          .order("guides.priority ASC")

    candidates.find do |gd|

      guide_skill_ids = gd.guide.skills.pluck(:id)

      (@required_skill_ids - guide_skill_ids).empty?

    end

  end

  def assign_skills_to_slot(slot)

    return if @required_skill_ids.empty?

    slot.skills = Skill.where(id: @required_skill_ids)

  end

  def increment_balance(guide)

    balance = MonthlyBalance.find_or_create_by(
      guide: guide,
      month: @month
    )

    balance.update!(
      worked_days: balance.worked_days.to_i + 1
    )

  end

end