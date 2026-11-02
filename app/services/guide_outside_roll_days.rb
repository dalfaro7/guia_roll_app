# Calendar dates: use the last recorded state of each day. Reactivation day
# is available; do not count future dates or infer historical inactive periods.
class GuideOutsideRollDays
  def self.call(guides:, month:)
    finish = [month.end_of_month, Date.current].min
    start = month.beginning_of_month
    events = GuideActivityChange.where(guide_id: guides.map(&:id))
      .order(:recorded_at, :id).group_by(&:guide_id)
    vacations = GuideDay.joins(:work_day)
      .where(guide_id: guides.map(&:id), status: :vacation, work_days: { date: start..finish })
      .pluck(:guide_id, "work_days.date").group_by(&:first)
    guides.to_h do |guide|
      history = events.fetch(guide.id, [])
      dates = vacations.fetch(guide.id, []).map(&:last).to_set
      (start..finish).each do |date|
        state = history.reverse.find { |event| event.recorded_at.in_time_zone.to_date <= date }
        dates << date if state && !state.active
      end
      coverage_start = [start, guide.created_at.in_time_zone.to_date].max
      complete = finish < coverage_start || history.any? { |e| e.recorded_at.in_time_zone.to_date <= coverage_start }
      [guide.id, { count: dates.size, complete: complete }]
    end
  end
end
