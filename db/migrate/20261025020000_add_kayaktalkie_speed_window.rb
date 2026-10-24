class AddKayaktalkieSpeedWindow < ActiveRecord::Migration[8.1]
  def change
    add_column :kayaktalkie_positions, :speed_samples, :jsonb, null: false, default: []
    add_column :kayaktalkie_positions, :speed_estimate, :jsonb, null: false, default: {}
  end
end
