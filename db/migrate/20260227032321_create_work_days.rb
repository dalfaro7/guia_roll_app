class CreateWorkDays < ActiveRecord::Migration[8.1]
  def change
    create_table :work_days do |t|
      t.date :date
      t.integer :guides_requested
      t.integer :status
      t.datetime :published_at

      t.timestamps
    end
  end
end
