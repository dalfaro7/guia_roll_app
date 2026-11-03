module Compensation
  class EditWindow
    def self.applicable?(work_day)
      return false unless work_day && CompensationRate.table_exists?

      first_rate = CompensationRate.minimum(:effective_at)
      first_rate && work_day.date >= first_rate.in_time_zone("America/Costa_Rica").to_date
    end

    def self.allowed?(user:, work_day:, now: Time.current)
      return false if user.blank? || work_day.blank?
      return true unless applicable?(work_day)
      return true if user.admin?
      return false unless user.operador?

      local_now = now.in_time_zone("America/Costa_Rica")
      return true if work_day.date > local_now.to_date
      return false if work_day.date < local_now.to_date

      local_now.hour < 18
    end
  end
end
