class VoiceChannel < ApplicationRecord
  belongs_to :kayaktalkie_team
  attr_readonly :kayaktalkie_team_id
  has_many :voice_memberships, dependent: :delete_all
  has_many :kayaktalkie_accounts, through: :voice_memberships
  scope :enabled, -> { where(active: true).order(:id) }
  validates :name, presence: true, length: { maximum: 80 }
  validates :room_key, presence: true, uniqueness: true, format: { with: /\A[a-z0-9-]{3,80}\z/ }
  def client_profile = { id: id, name: name, room: room_key, team_id: kayaktalkie_team_id, team_name: kayaktalkie_team.name }
end
