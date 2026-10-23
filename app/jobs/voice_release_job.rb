class VoiceReleaseJob < ApplicationJob
  retry_on VoiceTransport::Unavailable, wait: 2.seconds, attempts: 10
  def perform(floor_id, lease)
    floor = VoiceFloor.find_by(id: floor_id)
    return unless floor
    floor.with_lock do
      return unless floor.lease_id == lease && floor.holder_identity && floor.expires_at <= Time.current
      VoiceTransport.permission(floor.holder_identity, false, room: floor.room_key)
      floor.update!(holder_identity: nil, holder_name: nil, expires_at: nil, lease_id: nil)
    end
  end
end
