class AddPassengersToLocationSlots < ActiveRecord::Migration[7.0]
  def change
    add_column :location_slots, :passengers, :integer, default: 0
  end
end