class MobileAccount < ApplicationRecord
  belongs_to :guide, optional: true
  has_many :mobile_sessions, dependent: :delete_all
  has_many :voice_memberships, dependent: :delete_all
  has_many :voice_channels, through: :voice_memberships
  attr_reader :password
  before_validation { self.phone = self.class.normalize_phone(phone) }
  validates :phone, presence: true, uniqueness: true, format: { with: /\A\+[1-9]\d{7,14}\z/ }
  validates :guide_id, uniqueness: true, allow_nil: true
  validates :account_type, inclusion: { in: %w[guide office] }
  validates :guide, presence: true, if: :guide_account?
  validates :name, presence: true, if: :office_account?
  validates :guide_id, absence: true, if: :office_account?
  validates :location_enabled, inclusion: { in: [false] }, if: :office_account?
  def guide_account? = account_type == 'guide'
  def office_account? = account_type == 'office'
  def display_name = guide_account? ? guide&.name : name
  def available? = active? && (office_account? || (guide_account? && guide&.active?))
  def can_share_location? = guide_account? && location_enabled? && available?
  def client_profile
    { id: id, name: display_name, role: 'user', account_type: account_type,
      voice_channels: voice_channels.enabled.map(&:client_profile),
      capabilities: { voice: voice_channels.enabled.exists?, share_location: can_share_location? } }
  end
  validates :encrypted_password, presence: true
  validate { errors.add(:password, 'debe tener al menos 12 caracteres') if (new_record? || !@password.nil?) && @password.to_s.length < 12 }
  # Ocho dígitos sin prefijo corresponden a Costa Rica; otros países usan +código.
  def self.normalize_phone(value)
    raw = value.to_s.strip
    return nil unless raw.match?(/\A\+?[0-9 ()-]+\z/)
    digits = raw.gsub(/[^0-9]/, '')
    return "+506#{digits}" if !raw.start_with?('+') && digits.length == 8
    return "+#{digits}" if raw.start_with?('+') || (digits.length == 11 && digits.start_with?('506'))
    nil
  end
  def password=(value)
    @password = value
    self.encrypted_password = Devise::Encryptor.digest(User, value) if value.present?
  end
  def valid_password?(value)
    value.is_a?(String) && Devise::Encryptor.compare(User, encrypted_password, value)
  end
end
