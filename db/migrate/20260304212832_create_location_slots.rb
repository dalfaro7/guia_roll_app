class CreateLocationSlots < ActiveRecord::Migration[8.1]
  def change
    create_table :location_slots do |t|
      t.references :work_day, null: false, foreign_key: true
      t.string :location

      t.timestamps
    end
  end
end
