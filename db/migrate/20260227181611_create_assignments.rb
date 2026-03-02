class CreateAssignments < ActiveRecord::Migration[8.1]
  def change
    create_table :assignments do |t|
      t.references :work_day, null: false, foreign_key: true
      t.references :guide, null: false, foreign_key: true

      t.timestamps
    end
  end
end
