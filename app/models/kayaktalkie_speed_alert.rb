class KayaktalkieSpeedAlert < ApplicationRecord
  belongs_to :kayaktalkie_account
  validates :source, inclusion: { in: %w[gps estimated] }
  LIMIT_KMH = 90
  def self.record!(account, time, speed, source: 'gps')
    raise ArgumentError, 'Invalid speed source' unless %w[gps estimated].include?(source)
    day = time.in_time_zone('America/Costa_Rica').to_date
    active = where(kayaktalkie_account: account, source: source, ended_at: nil).first
    if active && (active.team_ids_at_capture.sort != account.kayaktalkie_team_ids.sort || active.day != day || time - active.last_at > 180)
      active.update!(ended_at: active.last_at)
      active = nil
    end
    if speed && speed > LIMIT_KMH
      if active
        active.update!(last_at: time, peak_kmh: [speed, active.peak_kmh].max)
      else
        create!(source: source, team_ids_at_capture: account.kayaktalkie_team_ids, kayaktalkie_account: account, account_name: account.name, day: day, first_at: time, last_at: time, peak_kmh: speed)
      end
    elsif active
      active.update!(ended_at: time)
    end
  end
end
