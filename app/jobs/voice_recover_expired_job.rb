class VoiceRecoverExpiredJob < ApplicationJob
  def perform
    VoiceFloor.where('expires_at <= ?', Time.current).where.not(holder_identity: nil).find_each do |floor|
      VoiceReleaseJob.perform_later(floor.id, floor.lease_id)
    end
  end
end
