class WorkDayVersion < ApplicationRecord
  belongs_to :work_day

  validates :snapshot, presence: true
end
