class GuideSpeedAlert < ApplicationRecord
  belongs_to :guide
  LIMIT_KMH = 90
  def self.record!(guide, time, speed)
    day = time.in_time_zone('America/Costa_Rica').to_date
    active = where(guide: guide, ended_at: nil).first
    if active && (active.day != day || time - active.last_at > 180)
      active.update!(ended_at: active.last_at)
      active = nil
    end
    if speed && speed > LIMIT_KMH
      if active
        active.update!(last_at: time, peak_kmh: [speed, active.peak_kmh].max)
      else
        create!(guide: guide, guide_name: guide.name, day: day, first_at: time, last_at: time, peak_kmh: speed)
      end
    elsif active
      active.update!(ended_at: time)
    end
  end
end
