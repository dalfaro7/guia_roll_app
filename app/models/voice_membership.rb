class VoiceMembership < ApplicationRecord
  belongs_to :kayaktalkie_account
  belongs_to :voice_channel
  validate { errors.add(:voice_channel, 'requiere pertenecer al equipo') unless kayaktalkie_account && voice_channel && kayaktalkie_account.kayaktalkie_teams.exists?(id: voice_channel.kayaktalkie_team_id) }
  validates :voice_channel_id, uniqueness: { scope: :kayaktalkie_account_id }
end
