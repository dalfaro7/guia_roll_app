class Bus < ApplicationRecord
  belongs_to :transport_company
  has_many :bus_assignments, dependent: :destroy
  has_many :location_slots, through: :bus_assignments

  before_validation :derive_size_category
  before_validation :sync_legacy_company

  validates :alias, :plate, presence: true
  validates :capacity, numericality: { only_integer: true, greater_than: 0 }
  validates :size_category, inclusion: { in: %w[small large] }
  validate :capacity_matches_category

  scope :available_on, ->(work_day) {
    where.not(id: BusAssignment.where(work_day_id: work_day.id).select(:bus_id))
  }

  def size_category_label
    size_category == "large" ? "Grande (20 o más pasajeros)" :
      "Pequeño (hasta 15 pasajeros)"
  end

  private

  def derive_size_category
    return if capacity.blank?

    self.size_category = if capacity.to_i.between?(1, 15)
      "small"
    elsif capacity.to_i >= 20
      "large"
    end
  end

  def capacity_matches_category
    return if capacity.blank?
    return if (size_category == "small" && capacity.to_i.between?(1, 15)) ||
      (size_category == "large" && capacity.to_i >= 20)

    errors.add(:capacity, "debe ser de 1 a 15 o de 20 pasajeros en adelante")
  end

  def sync_legacy_company
    self.company = transport_company.name if transport_company
  end
end
