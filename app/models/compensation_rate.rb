class CompensationRate < ApplicationRecord
  belongs_to :created_by, class_name: "User", optional: true

  CODES = %w[
    guide_apprentice guide_regular guide_invoice
    tl_balsa tl_sara hg_balsa hg_sara safety_kayak photographer
    driver_la_fortuna driver_bodega driver_hg driver_per_trip
    bonus_guide_drives bonus_photo_take_and_send bonus_photo_send_only
    bonus_photographer bonus_photographer_priority_zero bonus_bus_guide
  ].freeze

  validates :code, inclusion: { in: CODES }
  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :effective_at, presence: true, uniqueness: { scope: :code }

  before_update :immutable_rate
  before_destroy :immutable_rate
  after_commit :reprice_future_departures, on: :create

  def self.for(code, at:)
    where(code: code)
      .where("effective_at <= ?", at)
      .order(effective_at: :desc, id: :desc)
      .first
  end

  private

  def reprice_future_departures
    Departure.where("starts_at > ? AND starts_at >= ?", Time.current, effective_at)
      .where(status: "scheduled")
      .find_each do |departure|
        Compensation::RepriceDay.call(departure.work_day)
      end
  end

  def immutable_rate
    errors.add(:base, "Las tarifas publicadas no se modifican; cree una nueva vigencia")
    throw :abort
  end
end
