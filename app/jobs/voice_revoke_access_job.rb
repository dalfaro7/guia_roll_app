class VoiceRevokeAccessJob < ApplicationJob
  retry_on VoiceTransport::Unavailable, wait: 5.seconds, attempts: 12
  def perform(account_id, channel_id)
    account = MobileAccount.find_by(id: account_id)
    channel = VoiceChannel.find_by(id: channel_id)
    return unless account && channel
    # A delayed revocation must not remove a newly restored permission.
    return if account.voice_channels.exists?(id: channel.id)
    account.mobile_sessions.find_each do |session|
      VoiceTransport.disconnect("mobile-#{session.id}", room: channel.room_key)
    end
    floor = VoiceFloor.find_by(room_key: channel.room_key)
    floor&.with_lock do
      if account.mobile_sessions.exists?(id: floor.holder_identity.to_s.delete_prefix('mobile-'))
        floor.update!(holder_identity: nil, holder_name: nil, expires_at: nil, lease_id: nil)
      end
    end
  end
end
