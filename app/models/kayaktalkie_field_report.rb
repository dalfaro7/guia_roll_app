class KayaktalkieFieldReport < ApplicationRecord
  after_create_commit :notify_team
  def notify_team
    KayaktalkieNotifyFieldReportJob.perform_later(id)
  rescue StandardError
    Rails.logger.error("Report notification enqueue failed; recovery task will retry")
  end
  LIFETIME = 1.hour
  scope :unexpired, -> { where("created_at > ?", LIFETIME.ago) }
  scope :expired, -> { where("created_at <= ?", LIFETIME.ago) }
  def expires_at = created_at + LIFETIME
  KINDS = %w[emergency_sos road_accident controlled_traffic road_closed police_checkpoint wildlife strainer line_change dangerous_rapid].freeze
  ANIMALS = %w[monkeys sloths other].freeze
  belongs_to :kayaktalkie_account
  belongs_to :kayaktalkie_team
  belongs_to :resolved_by, class_name: 'KayaktalkieAccount', optional: true
  validates :kind, inclusion: {in: KINDS}
  validates :client_id, format: {with: /\A[a-zA-Z0-9_-]{16,80}\z/}
  validates :description, length: {maximum: 1000}
  validates :latitude, numericality: {greater_than_or_equal_to: -90, less_than_or_equal_to: 90}
  validates :longitude, numericality: {greater_than_or_equal_to: -180, less_than_or_equal_to: 180}
  validates :accuracy, numericality: {greater_than_or_equal_to: 0, less_than_or_equal_to: 1000}
  validates :observed_at, presence: true
  validate do
    errors.add(:animal, 'elige un animal') if kind == 'wildlife' && !ANIMALS.include?(animal)
    errors.add(:description, 'especifica el animal') if kind == 'wildlife' && animal == 'other' && description.blank?
    errors.add(:observed_at, 'debe ser reciente') if new_record? && observed_at && !observed_at.between?(24.hours.ago, 2.minutes.from_now)

  end
  def self.visible_to(account)
    account.admin? ? all : where(kayaktalkie_team_id: account.kayaktalkie_team_ids)
  end
  def client_profile
    {id: id, kind: kind, animal: animal, description: description, team_id: kayaktalkie_team_id,
     team: kayaktalkie_team.name, author: kayaktalkie_account.name, latitude: latitude, longitude: longitude,
     accuracy: accuracy, observed_at: observed_at.iso8601, received_at: created_at.iso8601, expires_at: expires_at.iso8601,
     resolved_at: resolved_at&.iso8601}
  end
end
