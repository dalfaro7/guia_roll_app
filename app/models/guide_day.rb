class GuideDay < ApplicationRecord
  belongs_to :guide
  belongs_to :work_day
  belongs_to :modified_by, class_name: "User", optional: true

  enum :status, {
    worked: 0,
    standby: 1,
    day_off: 2,
    vacation: 3
  }

  validates :status, presence: true
  before_save :apply_day_off_balance, if: :will_save_change_to_status?

  scope :ordered_for_display, -> {
    joins(:guide).order(
      Arel.sql("
        CASE guide_days.status
          WHEN 0 THEN 1
          WHEN 1 THEN 2
          ELSE 3
        END
      "),
      Arel.sql("
        CASE guide_days.location
          WHEN 'Sara-3&4' THEN 1
          WHEN 'Balsa' THEN 2
          WHEN 'Privado' THEN 3
          WHEN 'PM' THEN 4
          ELSE 5
        END
      "),
      "guides.priority ASC"
    )
  }

  def location_css_class
    case location
    when "Sara-3&4"
      "location-sara"
    when "Balsa"
      "location-balsa"
    when "PM"
      "location-pm"
    when "Privado"
      "location-privado"
    else
      ""
    end
  end


private

def apply_day_off_balance
  old_status = status_was
  new_status = status

  return unless new_status == "day_off"
  return if old_status == "day_off"
  return if day_off_consumed

  guide.consume_day_off!

  self.day_off_consumed = true
end

end