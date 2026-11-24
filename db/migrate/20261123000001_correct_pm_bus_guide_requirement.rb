class CorrectPmBusGuideRequirement < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE slot_skills AS assigned_skill
      SET skill_id = class_iii.id, updated_at = CURRENT_TIMESTAMP
      FROM location_slots AS slot, work_days AS day,
        skills AS class_iv, skills AS class_iii
      WHERE assigned_skill.location_slot_id = slot.id
        AND slot.work_day_id = day.id
        AND assigned_skill.skill_id = class_iv.id
        AND class_iv.name = 'ClassIV'
        AND class_iii.name = 'ClassIII'
        AND slot.location = 'PM'
        AND day.status IN (0, 1)
        AND day.date >= DATE '2026-11-24'
        AND (
          SELECT ARRAY_AGG(skill.name::text ORDER BY skill.name)
          FROM slot_skills AS requirement
          JOIN skills AS skill ON skill.id = requirement.skill_id
          WHERE requirement.location_slot_id = slot.id
        ) = ARRAY['Busguide', 'ClassIV', 'Computer']
    SQL

    execute <<~SQL
      DELETE FROM slot_skills AS assigned_skill
      USING location_slots AS slot, work_days AS day, skills AS class_iv
      WHERE assigned_skill.location_slot_id = slot.id
        AND slot.work_day_id = day.id
        AND assigned_skill.skill_id = class_iv.id
        AND class_iv.name = 'ClassIV'
        AND slot.location = 'PM'
        AND day.status IN (0, 1)
        AND day.date >= DATE '2026-11-24'
        AND (
          SELECT COUNT(*)
          FROM slot_skills AS requirement
          WHERE requirement.location_slot_id = slot.id
        ) = 1
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
