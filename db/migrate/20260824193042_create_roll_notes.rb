class CreateRollNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :roll_notes do |t|
      t.references :work_day, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }

      t.integer :note_type, null: false, default: 0
      t.text :note, null: false

      t.timestamps
    end

    create_table :roll_note_guide_days do |t|
      t.references :roll_note, null: false, foreign_key: true
      t.references :guide_day, null: false, foreign_key: true

      t.timestamps
    end

    add_index :roll_note_guide_days,
              [:roll_note_id, :guide_day_id],
              unique: true,
              name: "index_roll_note_guide_days_unique"
  end
end
