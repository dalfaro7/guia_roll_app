class GuideActivityChange < ApplicationRecord
  belongs_to :guide
  validates :recorded_at, presence: true
  validates :active, inclusion: { in: [true, false] }
end
