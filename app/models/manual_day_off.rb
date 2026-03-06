class ManualDayOff < ApplicationRecord
  belongs_to :guide

  validates :date, presence: true
end