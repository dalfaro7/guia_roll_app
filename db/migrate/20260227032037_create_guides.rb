class CreateGuides < ActiveRecord::Migration[8.1]
  def change
    create_table :guides do |t|
      t.string :name
      t.integer :priority
      t.boolean :active
      t.date :start_date
      t.integer :total_worked_days
      t.date :last_priority_change_date

      t.timestamps
    end
  end
end
