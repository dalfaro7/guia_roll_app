class VoiceMembership < ApplicationRecord
  belongs_to :mobile_account
  belongs_to :voice_channel
  validates :voice_channel_id, uniqueness: { scope: :mobile_account_id }
end
