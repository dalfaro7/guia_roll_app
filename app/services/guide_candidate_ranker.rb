class GuideCandidateRanker
  def initialize(work_day:, skill_ids: [])
    @work_day = work_day
    @skill_ids = Array(skill_ids).reject(&:blank?).map(&:to_i)
    @month = work_day.date.beginning_of_month
  end

  def standby_candidates
    candidates.select do |guide_day|
      guide_meets_required_skills?(guide_day.guide)
    end
  end

  def next_candidate
    standby_candidates.first
  end

  private

  def candidates
    GuideDay
      .available_for_date(@work_day.date)
      .where(work_day: @work_day)
      .includes(guide: [:skills, :monthly_balances])
      .sort_by do |guide_day|
        guide = guide_day.guide

        [
          guide.priority.to_i,
          worked_days_for_month(guide),
          guide.name.to_s
        ]
      end
  end

  def worked_days_for_month(guide)
    guide.monthly_balances.find do |balance|
      balance.month == @month
    end&.worked_days.to_i
  end

  def guide_meets_required_skills?(guide)
    return true if @skill_ids.empty?

    guide_skill_ids = guide.skills.map(&:id)
    (@skill_ids - guide_skill_ids).empty?
  end
end