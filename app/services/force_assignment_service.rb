class ForceAssignmentService
  attr_reader :guide

  def initialize(work_day, location, skills)
    @work_day = work_day
    @location = location
    @required_skill_ids = Array(skills).reject(&:blank?).map(&:to_i)
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

      @work_day.update!(
        guides_requested: @work_day.location_slots.count
      )

      guide_day.update!(
        status: :worked,
        location: @location,
        role_primary: "River Guide",
        manually_modified: true
      )
    end
  end

  private

  def next_available_guide_day
  GuideCandidateRanker.new(
    work_day: @work_day,
    skill_ids: @required_skill_ids
  ).next_candidate
end

  def assign_skills_to_slot(slot)
    return if @required_skill_ids.empty?

    slot.skills = Skill.where(id: @required_skill_ids)
  end
end