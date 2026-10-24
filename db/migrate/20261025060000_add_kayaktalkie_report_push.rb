class AddKayaktalkieReportPush < ActiveRecord::Migration[8.1]
  def change
    add_column :kayaktalkie_sessions, :expo_push_token, :string
    add_index :kayaktalkie_sessions, :expo_push_token, unique: true
    create_table :kayaktalkie_report_deliveries do |t|
      t.references :kayaktalkie_field_report, null: false, foreign_key: {on_delete: :cascade}, index: false
      t.references :kayaktalkie_session, null: false, foreign_key: {on_delete: :cascade}, index: false
      t.string :ticket_id
      t.string :status, null: false, default: 'pending'
      t.timestamps
    end
    add_index :kayaktalkie_report_deliveries, [:kayaktalkie_field_report_id, :kayaktalkie_session_id], unique: true, name: 'unique_report_push_recipient'
  end
end
