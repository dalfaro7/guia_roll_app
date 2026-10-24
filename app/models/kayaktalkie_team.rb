class KayaktalkieTeam < ApplicationRecord
  has_many :kayaktalkie_team_memberships, dependent: :restrict_with_error
  has_many :kayaktalkie_accounts, through: :kayaktalkie_team_memberships
  has_many :kayaktalkie_work_zones, dependent: :restrict_with_error
  has_many :voice_channels, dependent: :restrict_with_error
  validates :name, presence: true, length: {maximum: 80}
end
