class CreateKayaktalkieFieldReports < ActiveRecord::Migration[8.1]
  def change
    create_table :kayaktalkie_field_reports do |t|
      t.references :kayaktalkie_account, null: false, foreign_key: true
      t.references :kayaktalkie_team, null: false, foreign_key: true
      t.string :client_id, null: false
      t.string :kind, null: false
      t.string :animal
      t.text :description
      t.float :latitude, null: false
      t.float :longitude, null: false
      t.float :accuracy, null: false
      t.datetime :observed_at, null: false
      t.datetime :resolved_at
      t.references :resolved_by, foreign_key: {to_table: :kayaktalkie_accounts}
      t.timestamps
    end
    add_index :kayaktalkie_field_reports, [:kayaktalkie_account_id, :client_id], unique: true, name: 'unique_kayak_report_submission'
    add_index :kayaktalkie_field_reports, [:kayaktalkie_team_id, :resolved_at, :id], name: 'kayak_active_team_reports'
  end
end
