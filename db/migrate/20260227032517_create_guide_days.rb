class CreateGuideDays < ActiveRecord::Migration[8.1]
  def change
    create_table :guide_days do |t|
      t.references :guide, null: false, foreign_key: true
      t.references :work_day, null: false, foreign_key: true
      t.integer :status
      t.string :role_primary
      t.string :role_secondary
      t.boolean :manually_modified
      t.references :modified_by, foreign_key: { to_table: :users }, null: true

      t.timestamps
    end
  end
end
