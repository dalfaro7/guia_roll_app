module Compensation
  class EditWindow
    CUTOFF_HOUR = 20
    ZONE = "America/Costa_Rica"

    def self.cutoff_reached?(now: Time.current)
      now.in_time_zone(ZONE).hour >= CUTOFF_HOUR
    end

    def self.closed?(work_day, now: Time.current)
      return false unless applicable?(work_day)

      local_now = now.in_time_zone(ZONE)
      work_day.date < local_now.to_date ||
        (work_day.date == local_now.to_date && cutoff_reached?(now: now))
    end

    def self.applicable?(work_day)
      return false unless work_day&.date && CompensationRate.table_exists?

      first_rate = CompensationRate.minimum(:effective_at)
      first_rate && work_day.date >= first_rate.in_time_zone("America/Costa_Rica").to_date
    end

    def self.allowed?(user:, work_day:, now: Time.current)
      return false if user.blank? || work_day.blank?
      return true unless applicable?(work_day)
      return true if user.admin?
      return false unless user.operador? || user.hg_sarapiqui?

      !closed?(work_day, now: now)
    end
  end
end
