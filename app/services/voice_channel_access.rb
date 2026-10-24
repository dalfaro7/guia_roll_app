class VoiceChannelAccess
  def self.assign(account, channels)
    KayaktalkieAccess.assign!(account, attributes: {}, team_ids: account.kayaktalkie_team_ids, channel_ids: channels.map(&:id))
  end
end
