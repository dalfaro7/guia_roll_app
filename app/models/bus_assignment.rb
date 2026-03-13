class BusAssignment < ApplicationRecord
  belongs_to :bus
  belongs_to :work_day

  validates :location, presence: true
  validates :seats_assigned, numericality: { greater_than_or_equal_to: 0 }

  validate :cannot_exceed_bus_capacity
  validate :bus_cannot_be_used_twice_in_same_day


  def cannot_exceed_bus_capacity
    if seats_assigned.present? && seats_assigned > bus.capacity
      errors.add(:seats_assigned, "exceeds bus capacity")
    end
  end

  def bus_cannot_be_used_twice_in_same_day
  if BusAssignment
       .where(bus_id: bus_id, work_day_id: work_day_id)
       .where.not(id: id)
       .exists?

    errors.add(:bus_id, "is already assigned to another location today")
  end
end

end


