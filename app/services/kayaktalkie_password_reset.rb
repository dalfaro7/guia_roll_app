class KayaktalkiePasswordReset
  class InvalidToken < StandardError; end
  def self.request(email)
    account=KayaktalkieAccount.find_by(email: email.to_s.strip.downcase, active: true)
    return unless account&.email.present?
    token=SecureRandom.hex(32)
    account.with_lock do
      account.update_columns(reset_password_digest: Digest::SHA256.hexdigest(token), reset_password_sent_at: Time.current)
    end
    KayaktalkieMailer.password_reset(account.id, token).deliver_later
  end
  def self.consume!(token, password, confirmation)
    raise InvalidToken unless token.to_s.match?(/\A[a-f0-9]{64}\z/)
    account=KayaktalkieAccount.find_by(reset_password_digest: Digest::SHA256.hexdigest(token))
    raise InvalidToken unless account
    account.with_lock do
      raise InvalidToken unless account.active? && account.reset_password_digest == Digest::SHA256.hexdigest(token) && account.reset_password_sent_at && account.reset_password_sent_at > 1.hour.ago
      account.update!(password: password, password_confirmation: confirmation.to_s)
    end
    account
  end
end
