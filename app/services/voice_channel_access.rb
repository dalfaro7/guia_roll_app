class VoiceChannelAccess
  def self.assign(account, channels)
    account.with_lock do
      removed = account.voice_channels.where.not(id: channels.map(&:id)).to_a
      account.voice_channels = channels
      removed.each { |channel| VoiceRevokeAccessJob.perform_later(account.id, channel.id) }
    end
  end
end
