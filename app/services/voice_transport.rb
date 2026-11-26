class VoiceTransport
  class Unavailable < StandardError; end
  class ParticipantDisconnected < Unavailable; end
  def self.configured?
    ENV['LIVEKIT_URL'].present? && ENV['LIVEKIT_API_KEY'].present? && ENV['LIVEKIT_API_SECRET'].present?
  end
  def self.url
    raise Unavailable, 'El servidor de audio no está configurado.' unless configured?
    ENV.fetch('LIVEKIT_URL')
  end
  def self.token(identity, name, room: VoiceFloor::ROOM)
    url
    token = LiveKit::AccessToken.new(identity: identity, name: name, ttl: 300)
    token.video_grant = LiveKit::VideoGrant.new(roomJoin: true, room: room, canSubscribe: true, canPublish: false, canPublishData: false)
    token.to_jwt
  end
  def self.disconnect(identity, room:)
    service = VoiceRoomClient.new(url.sub(/^ws/, 'http'), api_key: ENV.fetch('LIVEKIT_API_KEY'), api_secret: ENV.fetch('LIVEKIT_API_SECRET'))
    service.remove_with_cutoff(room: room, identity: identity, cutoff: Time.current.to_i + 1)
  rescue Unavailable
    raise
  rescue StandardError => e
    return if e.respond_to?(:code) && e.code.to_s == 'not_found'
    Rails.logger.warn("Voice disconnect failed: #{e.class}")
    raise Unavailable, 'No se pudo retirar la conexion de voz; se reintentara.'
  end
  def self.permission(identity, publish, room: VoiceFloor::ROOM)
    service = LiveKit::RoomServiceClient.new(url.sub(/^ws/, 'http'), api_key: ENV.fetch('LIVEKIT_API_KEY'), api_secret: ENV.fetch('LIVEKIT_API_SECRET'))
    service.update_participant(room: room, identity: identity,
      permission: LiveKit::Proto::ParticipantPermission.new(can_subscribe: true, can_publish: publish, can_publish_data: false, can_publish_sources: [LiveKit::Proto::TrackSource::MICROPHONE]))
  rescue Unavailable
    raise
  rescue StandardError => e
    # Revoking a disconnected participant is already effective.
    return if !publish && e.respond_to?(:code) && e.code.to_s == 'not_found'
    code = e.respond_to?(:code) ? e.code.to_s : 'unknown'
    # Log only the SDK error code, never tokens, secrets, or server payloads.
    safe_code = %w[not_found permission_denied unauthenticated unavailable deadline_exceeded internal invalid_argument resource_exhausted].include?(code) ? code : 'unknown'
    Rails.logger.warn("Voice transport failed: #{e.class} code=#{safe_code}")
    if publish && code == 'not_found'
      raise ParticipantDisconnected, 'La conexión de voz se perdió. Desconecta y vuelve a conectar el canal para hablar.'
    end
    raise Unavailable, 'No se pudo comunicar con el servidor de audio. Se mantiene el micrófono apagado.'
  end
end
