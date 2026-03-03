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

end
