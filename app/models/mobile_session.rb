class MobileSession < ApplicationRecord
  belongs_to :mobile_account
  def self.issue!(account)
    token = SecureRandom.hex(32)
    account.mobile_sessions.create!(token_digest: Digest::SHA256.hexdigest(token), expires_at: 7.days.from_now)
    token
  end
  def self.authenticate(token)
    return if token.blank? || !token.match?(/\A[a-f0-9]{64}\z/)
    session = includes(mobile_account: :guide).find_by(token_digest: Digest::SHA256.hexdigest(token))
    session if session && session.expires_at > Time.current && session.mobile_account.available?
  end
end
