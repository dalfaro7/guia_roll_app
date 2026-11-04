module Compensation
  class DriverPaymentQuote
    def self.call(work_day:, bus:, driver:, location:)
      cost_cents = if bus.transport_company.internal_fleet?
        0
      else
        TransportRate.find_by(transport_company_id: bus.transport_company_id,
          location: location, vehicle_kind: bus.vehicle_kind,
          size_category: bus.size_category)&.amount_cents
      end
      result = { transport_cost_cents: cost_cents, driver_payment_cents: 0,
        explanation: "Sin chofer asignado" }
      return result unless driver
      unless bus.transport_company.internal_fleet?
        return result.merge(explanation: "El chofer lo paga la empresa externa")
      end

      role = DriverTransportSync::ROLE_BY_MODE[driver.payment_mode]
      return result.merge(explanation: "Sin pago directo configurado") unless role

      previous = BusAssignment.where(work_day_id: work_day.id, driver_id: driver.id)
        .order(:id).first
      if previous && driver.payment_mode != "per_trip"
        return result.merge(explanation: "Pago único del día registrado en la primera salida")
      end

      starts_at = Departure.fixed_start_for(work_day.date, location)
      rate = CompensationRate.for(role, at: starts_at)
      return result.merge(driver_payment_cents: nil,
        explanation: "Falta la tarifa del chofer") unless rate

      discount = if driver.payment_mode == "per_trip" && location == "PM" &&
          previous&.bus_id == bus.id && previous.location == "Sara-3&4" &&
          previous.outing_variant == "Sara-4"
        CompensationDiscountRule.for("second_sara", at: starts_at)&.percent
      else
        0
      end
      return result.merge(driver_payment_cents: nil,
        explanation: "Falta el descuento de la segunda salida") if discount.nil?

      amount = (rate.amount_cents * (100 - discount) + 50) / 100
      result.merge(driver_payment_cents: amount,
        explanation: discount.positive? ? "Segunda salida: descuento #{discount}%" :
          "Pago directo a este chofer")
    end
  end
end
