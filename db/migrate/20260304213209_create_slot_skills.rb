class CreateSlotSkills < ActiveRecord::Migration[8.1]
  def change
    create_table :slot_skills do |t|
      t.references :location_slot, null: false, foreign_key: true
      t.references :skill, null: false, foreign_key: true

      t.timestamps
    end
  end
end
