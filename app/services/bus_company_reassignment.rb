class BusCompanyReassignment
  class Conflict < StandardError; end

  def self.call(bus:, attributes:)
    new(bus, attributes).call
  end

  def initialize(bus, attributes)
    @bus = bus
    @attributes = attributes
  end

  def call
    Bus.transaction do
      @bus.lock!
      old_company = @bus.transport_company
      @bus.assign_attributes(@attributes)
      new_company = @bus.transport_company
      raise ActiveRecord::RecordInvalid, @bus unless new_company

      future_assignments = @bus.bus_assignments.joins(:work_day)
        .where("work_days.date > ?", Time.current.in_time_zone("America/Costa_Rica").to_date)
        .includes(:work_day, :driver, :compensation_assignment).order("work_days.date ASC, bus_assignments.id ASC").to_a
      updates = future_assignments.map do |assignment|
        validate_driver!(assignment, new_company)
        [assignment, rate_for!(assignment, new_company)]
      end

      @bus.company_reassignment_authorized = true
      @bus.save!
      updates.each do |assignment, cost_cents|
        assignment.update!(transport_company_snapshot: new_company,
          transport_company_name_snapshot: new_company.name,
          internal_fleet_snapshot: new_company.internal_fleet?,
          base_cost_cents: cost_cents, discount_cents: 0,
          discount_reason: nil, cost_cents: cost_cents)
      end
      { old_company_id: old_company.id, new_company_id: new_company.id,
        future_assignment_ids: updates.map { |assignment, _| assignment.id } }
    ensure
      @bus.company_reassignment_authorized = false
    end
  end

  private

  def validate_driver!(assignment, new_company)
    return unless assignment.driver

    if assignment.driver.transport_company_id.present? &&
        assignment.driver.transport_company_id != new_company.id
      raise Conflict, "La salida del #{assignment.work_day.date} tiene a #{assignment.driver.name} como chofer de otra empresa. Quite esa asignación antes de reasignar el bus."
    end
    if new_company.internal_fleet? != assignment.internal_fleet_snapshot?
      raise Conflict, "La salida del #{assignment.work_day.date} tiene un pago de chofer que cambiaría al pasar a flota #{new_company.internal_fleet? ? 'interna' : 'externa'}. Quite esa asignación antes de reasignar el bus."
    end
  end

  def rate_for!(assignment, new_company)
    return 0 if new_company.internal_fleet?

    rate = TransportRate.find_by(transport_company: new_company,
      location: assignment.location, vehicle_kind: @bus.vehicle_kind,
      size_category: @bus.size_category)
    raise Conflict, "Falta la tarifa de #{new_company.name} para #{assignment.location} y este bus." unless rate

    rate.amount_cents
  end
end
