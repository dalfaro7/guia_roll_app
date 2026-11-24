class PublicCurrentDistributionLink
  PURPOSE = :public_current_distribution
  PAYLOAD = "today_or_tomorrow"

  def self.token
    Rails.application.message_verifier(PURPOSE).generate(PAYLOAD)
  end

  def self.valid?(candidate)
    Rails.application.message_verifier(PURPOSE).verified(candidate) == PAYLOAD
  end
end
