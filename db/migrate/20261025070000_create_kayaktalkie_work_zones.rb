class CreateKayaktalkieWorkZones < ActiveRecord::Migration[8.0]
  def change
    create_table :kayaktalkie_work_zones do |t|
      t.references :kayaktalkie_team, null: false, foreign_key: true
      t.string :name, null: false, limit: 80
      t.float :latitude, null: false
      t.float :longitude, null: false
      t.integer :radius_m, null: false, default: 500
      t.timestamps
    end
  end
end
