class TransportRate < ApplicationRecord
  belongs_to :transport_company

  LOCATIONS = ["Balsa", "Sara-3&4", "PM", "Privado"].freeze
  CATEGORIES = %w[small large].freeze
  RATE_TYPES = [["bus", "small"], ["bus", "large"],
    ["four_by_four", "small"]].freeze

  validates :location, inclusion: { in: LOCATIONS },
    uniqueness: { scope: [:transport_company_id, :vehicle_kind, :size_category] }
  validates :size_category, inclusion: { in: CATEGORIES }
  validates :vehicle_kind, inclusion: { in: %w[bus four_by_four] }
  validate :four_by_four_must_be_small
  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def amount_usd
    dollars, cents = amount_cents.to_i.divmod(100)
    format("%d.%02d", dollars, cents)
  end

  def amount_usd=(value)
    text = value.to_s.strip
    self.amount_cents = text.match?(/\A\d+(?:\.\d{1,2})?\z/) ?
      (BigDecimal(text) * 100).to_i : nil
  end

  def category_label
    return "4x4 (hasta 15 espacios para guías)" if vehicle_kind == "four_by_four"

    size_category == "large" ? "Bus grande (20 o más pasajeros)" :
      "Bus pequeño (hasta 15 pasajeros)"
  end

  private

  def four_by_four_must_be_small
    if vehicle_kind == "four_by_four" && size_category != "small"
      errors.add(:size_category, "de un 4x4 debe ser pequeña")
    end
  end
end
