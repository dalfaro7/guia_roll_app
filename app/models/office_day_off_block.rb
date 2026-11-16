class OfficeDayOffBlock < ApplicationRecord
  belongs_to :created_by, class_name: "User"

  validates :date, presence: true, uniqueness: true
  validates :reason, length: { maximum: 250 }
end
