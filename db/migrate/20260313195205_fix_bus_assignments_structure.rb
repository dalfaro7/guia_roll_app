class FixBusAssignmentsStructure < ActiveRecord::Migration[7.0]
  def change

    remove_reference :bus_assignments, :location_slot, foreign_key: true

    add_reference :bus_assignments, :work_day, null: false, foreign_key: true

    add_column :bus_assignments, :location, :string, null: false

  end
end
