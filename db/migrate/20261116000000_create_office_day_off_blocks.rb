class CreateOfficeDayOffBlocks < ActiveRecord::Migration[8.1]
  def change
    create_table :office_day_off_blocks do |t|
      t.date :date, null: false
      t.string :reason, limit: 250
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :office_day_off_blocks, :date, unique: true
  end
end
