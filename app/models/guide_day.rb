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

  scope :ordered_for_display, -> {
  joins(:guide).order(
    Arel.sql("
      CASE guide_days.status
        WHEN 0 THEN 1   -- worked
        WHEN 1 THEN 2   -- standby
        ELSE 3
      END
    "),
    Arel.sql("
      CASE guide_days.location
        WHEN 'Sara-3&4' THEN 1
        WHEN 'Balsa' THEN 2
        WHEN 'Private' THEN 3
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
  when "Private"
    "location-private"
  else
    ""
  end
end

end
