class Bus < ApplicationRecord
  belongs_to :transport_company
  has_many :bus_assignments, dependent: :restrict_with_error
  has_many :location_slots, through: :bus_assignments

  attr_accessor :company_reassignment_authorized

  before_validation :derive_size_category
  before_validation :sync_legacy_company

  validates :alias, :plate, presence: true
  validates :capacity, numericality: { only_integer: true, greater_than: 0 }
  validates :size_category, inclusion: { in: %w[small large] }
  validates :vehicle_kind, inclusion: { in: %w[bus four_by_four] }
  validate :capacity_matches_category
  validate :company_offers_vehicle_category, if: :vehicle_category_changed?
  validate :preserve_assigned_vehicle_identity

  scope :available_on, ->(work_day) {
    where.not(id: BusAssignment.where(work_day_id: work_day.id).select(:bus_id))
  }

  def size_category_label
    return "4x4 para guías" if four_by_four?

    size_category == "large" ? "Grande (20 o más pasajeros)" :
      "Pequeño (hasta 15 pasajeros)"
  end

  def four_by_four?
    vehicle_kind == "four_by_four"
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

  def vehicle_category_changed?
    new_record? || will_save_change_to_transport_company_id? ||
      will_save_change_to_vehicle_kind? || will_save_change_to_capacity?
  end

  def company_offers_vehicle_category
    return unless transport_company && vehicle_kind.present? && size_category.present?
    return if transport_company.offers_vehicle_category?(
      vehicle_kind: vehicle_kind, size_category: size_category)

    errors.add(:transport_company, "no ofrece esta categoría de vehículo")
  end

  def preserve_assigned_vehicle_identity
    return unless persisted? && bus_assignments.exists?
    if will_save_change_to_vehicle_kind?
      errors.add(:base, "No puede cambiar el tipo de un vehículo ya asignado")
    end
    if will_save_change_to_transport_company_id? && !company_reassignment_authorized
      errors.add(:base, "Use la reasignación de empresa para conservar los viajes anteriores")
    end
  end

  def capacity_matches_category
    return if capacity.blank?
    if four_by_four? && capacity.to_i > 15
      errors.add(:capacity, "de un 4x4 no puede superar 15 espacios para guías")
    end
    return if (size_category == "small" && capacity.to_i.between?(1, 15)) ||
      (size_category == "large" && capacity.to_i >= 20)

    errors.add(:capacity, "debe ser de 1 a 15 o de 20 pasajeros en adelante")
  end

  def sync_legacy_company
    self.company = transport_company.name if transport_company
  end
end
