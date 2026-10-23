class VoiceTurn
  class Occupied < StandardError; end
  def self.claim(identity, name, channel: nil)
    floor = channel ? VoiceFloor.for_channel(channel) : VoiceFloor.general
    failure = nil
    result = nil
    floor.with_lock do
      raise Occupied if floor.holder_identity && floor.expires_at > Time.current
      # Revoke the previous publisher before granting the next, including stale leases.
      VoiceTransport.permission(floor.holder_identity, false, room: floor.room_key) if floor.holder_identity
      lease = SecureRandom.hex(16)
      floor.update!(holder_identity: identity, holder_name: name, expires_at: VoiceFloor::MAX_SECONDS.seconds.from_now, lease_id: lease)
      VoiceReleaseJob.set(wait_until: floor.expires_at).perform_later(floor.id, lease)
      begin
        # Reserve and schedule recovery before a network call that may succeed but time out.
        VoiceTransport.permission(identity, true, room: floor.room_key)
        result = { lease: lease, expiresAt: (floor.expires_at.to_f * 1000).round }
      rescue VoiceTransport::Unavailable => e
        failure = e
      end
    end
    raise failure if failure
    result
  end
  def self.release(identity, lease, channel: nil)
    floor = channel ? VoiceFloor.for_channel(channel) : VoiceFloor.general
    floor.with_lock do
      return false unless floor.holder_identity == identity && floor.lease_id == lease
      VoiceTransport.permission(identity, false, room: floor.room_key)
      floor.update!(holder_identity: nil, holder_name: nil, expires_at: nil, lease_id: nil)
    end
    true
  end
end
