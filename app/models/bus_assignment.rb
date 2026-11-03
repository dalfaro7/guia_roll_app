class BusAssignment < ApplicationRecord
  belongs_to :bus
  belongs_to :work_day
  belongs_to :driver, optional: true

  validates :location, presence: true
  validates :seats_assigned, numericality: { greater_than_or_equal_to: 0 }
  validates :cost_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def cost_usd
    dollars, cents = cost_cents.to_i.divmod(100)
    format("%d.%02d", dollars, cents)
  end

  def cost_usd=(value)
    text = value.to_s.strip
    self.cost_cents = text.match?(/\A\d+(?:\.\d{1,2})?\z/) ?
      (BigDecimal(text) * 100).to_i : nil
  end

  validate :cannot_exceed_bus_capacity
  validate :bus_cannot_be_used_twice_in_same_day
  validate :driver_belongs_to_bus_company

  private

  def cannot_exceed_bus_capacity
    if seats_assigned.present? && bus && seats_assigned > bus.capacity
      errors.add(:seats_assigned, "supera la capacidad del bus")
    end
  end

  def bus_cannot_be_used_twice_in_same_day
    return if bus_id.blank? || work_day_id.blank?

    if BusAssignment.where(bus_id: bus_id, work_day_id: work_day_id)
        .where.not(id: id).exists?
      errors.add(:bus, "ya está asignado a una salida de este día")
    end
  end

  def driver_belongs_to_bus_company
    return unless driver && bus
    return if driver.transport_company_id == bus.transport_company_id

    errors.add(:driver, "debe pertenecer a la empresa del bus")
  end
end
