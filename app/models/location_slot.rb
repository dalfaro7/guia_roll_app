class LocationSlot < ApplicationRecord
  belongs_to :work_day

  has_many :slot_skills, dependent: :destroy
  has_many :skills, through: :slot_skills
end
