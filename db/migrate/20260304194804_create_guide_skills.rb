class CreateGuideSkills < ActiveRecord::Migration[8.1]
  def change
    create_table :guide_skills do |t|
      t.references :guide, null: false, foreign_key: true
      t.references :skill, null: false, foreign_key: true

      t.timestamps
    end

    add_index :guide_skills, [:guide_id, :skill_id], unique: true
  end
end
