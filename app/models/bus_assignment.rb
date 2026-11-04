class BusAssignment < ApplicationRecord
  belongs_to :bus
  belongs_to :work_day
  belongs_to :driver, optional: true
  belongs_to :compensation_assignment, optional: true

  validates :location, presence: true
  validates :location, inclusion: { in: TransportRate::LOCATIONS }, on: :create
  validates :seats_assigned, numericality: { greater_than_or_equal_to: 0 }
  validates :cost_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :outing_variant, inclusion: { in: %w[Sara-3 Sara-4] }, allow_nil: true
  validate :cannot_exceed_bus_capacity
  validate :vehicle_and_driver_available, if: :transport_identity_changed?
  validate :driver_belongs_to_bus_company, if: :transport_identity_changed?
  validate :sara_variant_for_four_by_four, if: :transport_identity_changed?
  before_validation :snapshot_fleet_type, on: :create
  before_validation :apply_transport_rate, on: :create
  after_create :sync_driver_payment
  before_destroy :prevent_removing_first_leg
  after_destroy :cancel_driver_payment

  def cost_usd
    dollars, cents = cost_cents.to_i.divmod(100)
    format("%d.%02d", dollars, cents)
  end

  def cost_usd=(value)
    text = value.to_s.strip
    self.cost_cents = text.match?(/\A\d+(?:\.\d{1,2})?\z/) ?
      (BigDecimal(text) * 100).to_i : nil
  end

  def driver_payment_cents
    compensation_assignment&.total_cents.to_i
  end

  private

  def transport_identity_changed?
    new_record? || %w[bus_id work_day_id driver_id location outing_variant].any? do |attribute|
      will_save_change_to_attribute?(attribute)
    end
  end

  def snapshot_fleet_type
    self.internal_fleet_snapshot = bus.transport_company.internal_fleet? if bus
  end

  def apply_transport_rate
    return unless bus && location.present?

    if internal_fleet_snapshot?
      self.cost_cents = 0
    else
      rate = TransportRate.find_by(transport_company_id: bus.transport_company_id,
        location: location, vehicle_kind: bus.vehicle_kind,
        size_category: bus.size_category)
      if rate
        self.cost_cents = rate.amount_cents
      elsif TransportRate::LOCATIONS.include?(location)
        errors.add(:base, "No hay tarifa de transporte para esta empresa, salida y categoría")
      end
    end
  end

  def cannot_exceed_bus_capacity
    if seats_assigned.present? && bus && seats_assigned > bus.capacity
      errors.add(:seats_assigned, "supera la capacidad del vehículo")
    end
  end

  def vehicle_and_driver_available
    return unless bus && work_day && location

    unless VehicleAvailability.available?(bus: bus, work_day: work_day,
        location: location, outing_variant: outing_variant, driver: driver,
        excluding: self, require_matching_driver: true)
      errors.add(:bus, "ya está asignado a una salida incompatible de este día")
    end
    if driver && !DriverEligibility.available?(driver: driver, bus: bus,
        work_day: work_day, location: location, outing_variant: outing_variant,
        excluding: self)
      errors.add(:driver, "ya está asignado a otra salida de este día")
    end
  end

  def driver_belongs_to_bus_company
    return unless driver && bus
    errors.add(:driver, "no está activo") unless driver.active?
    return if driver.transport_company_id.nil? ||
      driver.transport_company_id == bus.transport_company_id

    errors.add(:driver, "debe pertenecer a la empresa del vehículo")
  end

  def sara_variant_for_four_by_four
    if outing_variant.present? && location != "Sara-3&4"
      errors.add(:outing_variant, "solo corresponde a Sara 3 y 4")
    elsif bus&.four_by_four? && location == "Sara-3&4" && outing_variant.blank?
      errors.add(:outing_variant, "indique Sara clase 3 o clase 4")
    end
  end

  def sync_driver_payment
    Compensation::DriverTransportSync.call(self)
  end

  def prevent_removing_first_leg
    return unless bus&.four_by_four? && location == "Sara-3&4" &&
      outing_variant == "Sara-4"
    if BusAssignment.where(bus_id: bus_id, work_day_id: work_day_id,
        location: "PM").exists?
      errors.add(:base, "Quite primero la salida PM de este 4x4")
      throw :abort
    end
  end

  def cancel_driver_payment
    return unless compensation_assignment

    compensation_assignment.update!(status: "canceled")
    Compensation::RepriceDay.call(work_day, driver: driver)
  end
end
