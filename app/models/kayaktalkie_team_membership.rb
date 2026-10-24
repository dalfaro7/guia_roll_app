class KayaktalkieTeamMembership < ApplicationRecord
  belongs_to :kayaktalkie_account
  belongs_to :kayaktalkie_team
  validates :kayaktalkie_account_id, uniqueness: {scope: :kayaktalkie_team_id}
end
