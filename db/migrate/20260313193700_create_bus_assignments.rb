class CreateBusAssignments < ActiveRecord::Migration[8.1]
  def change
    create_table :bus_assignments do |t|
      t.references :bus, null: false, foreign_key: true
      t.references :location_slot, null: false, foreign_key: true
      t.integer :seats_assigned

      t.timestamps
    end
  end
end
