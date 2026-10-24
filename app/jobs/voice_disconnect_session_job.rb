class VoiceDisconnectSessionJob < ApplicationJob
  retry_on VoiceTransport::Unavailable, wait: 5.seconds, attempts: 12
  def perform(identity, room_keys)
    room_keys.each { |room| VoiceTransport.disconnect(identity, room: room) }
  end
end
