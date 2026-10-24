class SeparateKayaktalkieSpeedAlertSources < ActiveRecord::Migration[8.1]
  def up
    add_column :kayaktalkie_speed_alerts, :source, :string, null: false, default: 'gps'
    add_check_constraint :kayaktalkie_speed_alerts, "source IN ('gps', 'estimated')", name: 'kayaktalkie_speed_alert_source'
    remove_index :kayaktalkie_speed_alerts, name: 'one_open_kayaktalkie_speed_alert'
    add_index :kayaktalkie_speed_alerts, [:kayaktalkie_account_id, :source], unique: true, where: 'ended_at IS NULL', name: 'one_open_kayaktalkie_speed_alert_per_source'
  end
  def down
    raise ActiveRecord::IrreversibleMigration, 'Separate speed histories must be preserved; restore the pre-migration backup if rollback is required.'
  end
end
