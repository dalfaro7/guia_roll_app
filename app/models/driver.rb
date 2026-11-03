class Driver < ApplicationRecord
  has_many :compensation_assignments, dependent: :restrict_with_error
  has_many :compensation_settlements, dependent: :restrict_with_error

  validates :name, presence: true

  scope :active, -> { where(active: true) }
end
