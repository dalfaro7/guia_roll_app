class VoiceFloor < ApplicationRecord
  ROOM = 'guide-team-general'
  MAX_SECONDS = 30
  def self.for_channel(channel)
    create_or_find_by!(room_key: channel.room_key)
  end
  def self.general
    create_or_find_by!(room_key: ROOM)
  end
end
