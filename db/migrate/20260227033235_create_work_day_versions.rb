class CreateWorkDayVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :work_day_versions do |t|
      t.references :work_day, null: false, foreign_key: true
      t.jsonb :snapshot

      t.timestamps
    end
  end
end
