class Departure < ApplicationRecord
  OPERATING_SECTIONS = {
    "Balsa" => ["Balsa"],
    "Sara-3&4" => ["Sara-3&4", "Sara-3", "Sara-4"],
    "PM" => ["PM"],
    "Privado" => ["Privado"]
  }.freeze
  FIXED_START_TIMES = {
    "Balsa" => [9, 20],
    "Sara-3&4" => [8, 20],
    "Sara-3" => [8, 20],
    "Sara-4" => [8, 20],
    "PM" => [11, 20],
    "Privado" => [8, 20]
  }.freeze

  LEADER_RATE_SUFFIX = {
    "Balsa" => "balsa",
    "Sara-3&4" => "sara",
    "Sara-3" => "sara",
    "Sara-4" => "sara",
    "PM" => "sara"
  }.freeze

  def self.leader_rate_suffix_for(location)
    LEADER_RATE_SUFFIX[location]
  end

  def self.fixed_start_for(date, location)
    hour, minute = FIXED_START_TIMES.fetch(location)
    Time.find_zone!("America/Costa_Rica").local(date.year, date.month, date.day,
      hour, minute)
  end

  belongs_to :work_day
  has_many :compensation_assignments, dependent: :restrict_with_error

  validates :label, :location, :starts_at, presence: true
  validates :label, uniqueness: { scope: :work_day_id }
  validates :status, inclusion: { in: %w[scheduled completed canceled] }
  validate :starts_on_work_day
  validate :one_balsa_per_day

  scope :chronological, -> { order(:starts_at, :id) }

  after_commit :reprice_after_schedule_change,
               on: :update,
               if: :saved_change_to_starts_at?

  def started?
    starts_at.present? && starts_at <= Time.current
  end

  def closed?
    closed_at.present?
  end

  private

  def reprice_after_schedule_change
    Compensation::RepriceDay.call(work_day)
  end

  def starts_on_work_day
    return if starts_at.blank? || work_day.blank? || work_day.date.blank?

    unless starts_at.in_time_zone("America/Costa_Rica").to_date == work_day.date
      errors.add(:starts_at, "debe corresponder a la fecha de la programación")
    end
  end

  def one_balsa_per_day
    return unless location == "Balsa" && work_day.present?

    others = work_day.departures.where(location: "Balsa")
    others = others.where.not(id: id) if persisted?
    errors.add(:location, "solo permite una salida Balsa por día") if others.exists?
  end
end
