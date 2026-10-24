require 'bcrypt'
class KayaktalkieAccount < ApplicationRecord
  has_many :kayaktalkie_sessions, dependent: :restrict_with_error
  has_many :voice_memberships, dependent: :destroy
  has_many :voice_channels, through: :voice_memberships
  has_many :kayaktalkie_team_memberships, dependent: :destroy
  has_many :kayaktalkie_teams, through: :kayaktalkie_team_memberships
  has_one :kayaktalkie_position, dependent: :restrict_with_error
  has_many :kayaktalkie_speed_alerts, dependent: :restrict_with_error
  belongs_to :created_by, class_name: 'KayaktalkieAccount', optional: true
  before_validation { self.email = email.to_s.strip.downcase.presence }
  validates :email, format: {with: URI::MailTo::EMAIL_REGEXP}, uniqueness: {case_sensitive: false}, allow_nil: true, length: {maximum: 254}
  attr_accessor :password_confirmation
  validates :password, confirmation: true
  after_update :invalidate_password_access
  def invalidate_password_access
    if saved_change_to_encrypted_password? || saved_change_to_email? || saved_change_to_active?
      update_columns(reset_password_digest: nil, reset_password_sent_at: nil)
    end
    kayaktalkie_sessions.destroy_all if saved_change_to_encrypted_password? || (saved_change_to_active? && !active?)
  end
  attr_reader :password
  before_validation { self.phone = self.class.normalize_phone(phone) }
  validates :phone, presence: true, uniqueness: true, format: { with: /\A\+[1-9]\d{7,14}\z/ }
  validates :name, presence: true, length: { maximum: 100 }
  validates :role, inclusion: { in: %w[admin operator staff] }
  validates :encrypted_password, presence: true
  validate { errors.add(:password, 'debe tener al menos 12 caracteres') if (new_record? || !@password.nil?) && @password.to_s.length < 12 }
  def admin? = role == 'admin'
  def operator? = role == 'operator'
  def staff? = role == 'staff'
  def map_access? = admin? || operator?
  def display_name = name
  def available? = active?
  def can_share_location? = active? && location_enabled?
  def allowed_channels
    return VoiceChannel.enabled if admin?
    voice_channels.enabled.where(kayaktalkie_team_id: kayaktalkie_teams.select(:id))
  end
  def client_profile
    { id: id, name: name, role: role, map_area: map_access? ? map_area : nil, teams: kayaktalkie_teams.order(:name).map { |t| {id: t.id,name: t.name} },
      voice_channels: allowed_channels.map(&:client_profile),
      capabilities: { voice: allowed_channels.exists?, share_location: can_share_location?, map: map_access?, manage_accounts: admin? } }
  end
  def self.normalize_phone(value)
    raw=value.to_s.strip
    return nil unless raw.match?(/\A\+?[0-9 ()-]+\z/)
    digits=raw.gsub(/[^0-9]/,'')
    return "+506#{digits}" if !raw.start_with?('+') && digits.length==8
    return "+#{digits}" if raw.start_with?('+') || (digits.length==11 && digits.start_with?('506'))
    nil
  end
  def password=(value)
    @password=value
    self.encrypted_password=BCrypt::Password.create(value + Devise.pepper.to_s, cost: Rails.env.test? ? 4 : 12).to_s if value.present?
  end
  def valid_password?(value)
    value.is_a?(String) && BCrypt::Password.new(encrypted_password).is_password?(value + Devise.pepper.to_s)
  rescue BCrypt::Errors::InvalidHash
    false
  end
end
