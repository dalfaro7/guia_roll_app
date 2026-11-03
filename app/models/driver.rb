class Driver < ApplicationRecord
  belongs_to :transport_company
  has_many :bus_assignments, dependent: :nullify
  has_many :compensation_assignments, dependent: :restrict_with_error
  has_many :compensation_settlements, dependent: :restrict_with_error

  validates :name, presence: true
  validates :phone, presence: true, on: :create

  scope :active, -> { where(active: true) }
end
