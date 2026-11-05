class Driver < ApplicationRecord
  belongs_to :transport_company, optional: true
  has_many :bus_assignments, dependent: :restrict_with_error
  has_many :compensation_assignments, dependent: :restrict_with_error
  has_many :compensation_settlements, dependent: :restrict_with_error

  validates :name, presence: true
  validates :payment_mode, inclusion: { in: %w[none per_trip daily_hg round_trip] }

  scope :active, -> { where(active: true) }
end
