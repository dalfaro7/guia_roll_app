module BusesHelper
  def bus_capacity_label(bus)
    "#{bus.capacity} #{bus.capacity == 1 ? 'pasajero' : 'pasajeros'}"
  end
end
