class CreateManualDayOffs < ActiveRecord::Migration[8.1]
  def change
    create_table :manual_day_offs do |t|
      t.references :guide, null: false, foreign_key: true
      t.date :date, null: false

      t.timestamps
    end

    add_index :manual_day_offs, [:guide_id, :date], unique: true
  end
end