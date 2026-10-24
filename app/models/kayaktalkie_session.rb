class KayaktalkieSession < ApplicationRecord
  belongs_to :kayaktalkie_account
  before_destroy do
    rooms = kayaktalkie_account.allowed_channels.pluck(:room_key)
    VoiceDisconnectSessionJob.perform_later("mobile-#{id}", rooms) if rooms.any?
  end
  def self.issue!(account)
    token = SecureRandom.hex(32)
    account.kayaktalkie_sessions.create!(token_digest: Digest::SHA256.hexdigest(token), expires_at: 7.days.from_now)
    token
  end
  def self.authenticate(token)
    return if token.blank? || !token.match?(/\A[a-f0-9]{64}\z/)
    session = includes(:kayaktalkie_account).find_by(token_digest: Digest::SHA256.hexdigest(token))
    session if session && session.expires_at > Time.current && session.kayaktalkie_account.available?
  end
end
