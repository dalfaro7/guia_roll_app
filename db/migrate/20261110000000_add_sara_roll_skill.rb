class AddSaraRollSkill < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      INSERT INTO skills (name, created_at, updated_at)
      SELECT 'Roll de Sara', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      WHERE NOT EXISTS (SELECT 1 FROM skills WHERE name = 'Roll de Sara')
    SQL
  end

  def down
    execute <<~SQL
      DELETE FROM skills
      WHERE name = 'Roll de Sara'
        AND NOT EXISTS (
          SELECT 1 FROM guide_skills WHERE guide_skills.skill_id = skills.id
        )
        AND NOT EXISTS (
          SELECT 1 FROM slot_skills WHERE slot_skills.skill_id = skills.id
        )
    SQL
  end
end
