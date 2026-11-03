class TransportRate < ApplicationRecord
  LOCATIONS = ["Balsa", "Sara-3&4", "PM", "Privado"].freeze
  CATEGORIES = %w[small large].freeze

  validates :location, inclusion: { in: LOCATIONS }, uniqueness: { scope: :size_category }
  validates :size_category, inclusion: { in: CATEGORIES }
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
    size_category == "large" ? "Grande (20 o más pasajeros)" : "Pequeño (hasta 15 pasajeros)"
  end
end
