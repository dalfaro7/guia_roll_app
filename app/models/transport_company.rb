class TransportCompany < ApplicationRecord
  VEHICLE_CATEGORY_TYPES = {
    "bus_small" => ["bus", "small"],
    "bus_large" => ["bus", "large"],
    "four_by_four" => ["four_by_four", "small"]
  }.freeze
  VEHICLE_CATEGORY_LABELS = {
    "bus_small" => "Bus pequeño (hasta 15 pasajeros)",
    "bus_large" => "Bus grande (20 o más pasajeros)",
    "four_by_four" => "4x4 (espacios para guías)"
  }.freeze

  has_many :buses, dependent: :restrict_with_error
  has_many :drivers, dependent: :restrict_with_error
  has_many :transport_rates, dependent: :restrict_with_error

  after_create :create_default_transport_rates

  validates :internal_fleet, inclusion: { in: [true, false] }

  before_validation :normalize_name
  before_validation :normalize_vehicle_categories

  validate :vehicle_categories_are_supported
  validates :name, presence: true, uniqueness: { case_sensitive: false }

  def offers_vehicle_category?(vehicle_kind:, size_category:)
    category = VEHICLE_CATEGORY_TYPES.find do |_code, type|
      type == [vehicle_kind, size_category]
    end&.first
    category.present? && vehicle_categories.include?(category)
  end

  private

  def normalize_vehicle_categories
    self.vehicle_categories = Array(vehicle_categories).reject(&:blank?).uniq
  end

  def vehicle_categories_are_supported
    if vehicle_categories.empty?
      errors.add(:vehicle_categories, "debe incluir al menos una categoría")
    elsif (vehicle_categories - VEHICLE_CATEGORY_TYPES.keys).any?
      errors.add(:vehicle_categories, "contiene una categoría no válida")
    end
  end

  def create_default_transport_rates
    TransportRate::LOCATIONS.each do |location|
      TransportRate::RATE_TYPES.each do |kind, category|
        transport_rates.create!(location: location, vehicle_kind: kind,
          size_category: category, amount_cents: 12_000)
      end
    end
  end

  def normalize_name
    self.name = name.to_s.strip
  end
end
