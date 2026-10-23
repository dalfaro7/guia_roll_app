# The installed SDK exposes the protobuf cutoff field but not a convenience option.
class VoiceRoomClient < LiveKit::RoomServiceClient
  def remove_with_cutoff(room:, identity:, cutoff:)
    rpc!(:RemoveParticipant,
      LiveKit::Proto::RoomParticipantIdentity.new(room: room, identity: identity, revoke_token_ts: cutoff),
      headers: auth_header(video_grant: LiveKit::VideoGrant.new(roomAdmin: true, room: room)))
  end
end
