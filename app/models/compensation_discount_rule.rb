class CompensationDiscountRule < ApplicationRecord
  CODES = %w[second_sara second_other].freeze

  belongs_to :created_by, class_name: "User", optional: true

  validates :code, inclusion: { in: CODES }
  validates :percent, numericality: {
    only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100
  }
  validates :effective_at, presence: true, uniqueness: { scope: :code }

  before_update :immutable_rule
  before_destroy :immutable_rule
  after_commit :reprice_future_departures, on: :create

  def self.for(code, at:)
    where(code: code)
      .where("effective_at <= ?", at)
      .order(effective_at: :desc, id: :desc)
      .first
  end

  private

  def immutable_rule
    errors.add(:base, "Los descuentos publicados no se modifican; cree una nueva vigencia")
    throw :abort
  end

  def reprice_future_departures
    Departure.where("starts_at > ? AND starts_at >= ?", Time.current, effective_at)
      .where(status: "scheduled")
      .find_each { |departure| Compensation::RepriceDay.call(departure.work_day) }
  end
end
