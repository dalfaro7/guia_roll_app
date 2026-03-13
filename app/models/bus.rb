class Bus < ApplicationRecord
  has_many :bus_assignments, dependent: :destroy
  has_many :location_slots, through: :bus_assignments

  validates :alias, presence: true
  validates :plate, presence: true
  validates :capacity, numericality: { greater_than: 0 }
end

