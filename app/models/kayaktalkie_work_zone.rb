class KayaktalkieWorkZone < ApplicationRecord
  belongs_to :kayaktalkie_team
  belongs_to :operator, class_name: 'KayaktalkieAccount'
  validate do
    unless operator&.operator? && operator.active? && operator.kayaktalkie_team_ids.include?(kayaktalkie_team_id)
      errors.add(:operator, 'debe ser un operador activo del equipo')
    end
  end
  validates :name, presence: true, length: {maximum: 80}
  validates :latitude, numericality: {greater_than_or_equal_to: -85, less_than_or_equal_to: 85}
  validates :longitude, numericality: {greater_than_or_equal_to: -180, less_than_or_equal_to: 180}
  validates :radius_m, numericality: {only_integer: true, greater_than_or_equal_to: 10, less_than_or_equal_to: 50000}
end
