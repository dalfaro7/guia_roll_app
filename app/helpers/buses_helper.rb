module BusesHelper
  def bus_capacity_label(bus)
    person = bus.four_by_four? ? (bus.capacity == 1 ? "guía" : "guías") :
      (bus.capacity == 1 ? "pasajero" : "pasajeros")
    "#{bus.capacity} #{person}"
  end
end
