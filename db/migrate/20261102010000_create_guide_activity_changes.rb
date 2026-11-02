class CreateGuideActivityChanges < ActiveRecord::Migration[8.1]
  def up
    create_table :guide_activity_changes do |t|
      t.references :guide, null: false, foreign_key: true
      t.boolean :active, null: false
      t.datetime :recorded_at, null: false
    end
    add_index :guide_activity_changes, [:guide_id, :recorded_at]
    execute <<~SQL
      INSERT INTO guide_activity_changes (guide_id, active, recorded_at)
      SELECT id, COALESCE(active, FALSE), CURRENT_TIMESTAMP FROM guides
    SQL
  end

  def down
    drop_table :guide_activity_changes
  end
end
