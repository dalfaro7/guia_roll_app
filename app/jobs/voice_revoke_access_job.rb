class VoiceRevokeAccessJob < ApplicationJob
  retry_on VoiceTransport::Unavailable, wait: 5.seconds, attempts: 12
  def perform(account_id, channel_id, previous_identities = [])
    account = KayaktalkieAccount.find_by(id: account_id)
    channel = VoiceChannel.find_by(id: channel_id)
    return unless account && channel
    # A delayed revocation must not remove a newly restored permission.
    return if account.available? && account.allowed_channels.exists?(id: channel.id)
    identities = (Array(previous_identities) + account.kayaktalkie_sessions.pluck(:id).map { |id| "mobile-#{id}" }).uniq
    identities.each do |identity|
      VoiceTransport.disconnect(identity, room: channel.room_key)
    end
    floor = VoiceFloor.find_by(room_key: channel.room_key)
    floor&.with_lock do
      if identities.include?(floor.holder_identity)
        floor.update!(holder_identity: nil, holder_name: nil, expires_at: nil, lease_id: nil)
      end
    end
  end
end
