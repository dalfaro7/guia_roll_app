class CreateGuideTracking < ActiveRecord::Migration[8.1]
  def change
    create_table :mobile_accounts do |t|
      t.references :guide, null: false, foreign_key: true, index: { unique: true }
      t.string :email, null: false
      t.string :encrypted_password, null: false
      t.boolean :active, default: true, null: false
      t.timestamps
    end
    add_index :mobile_accounts, :email, unique: true
    create_table :mobile_sessions do |t|
      t.references :mobile_account, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :mobile_sessions, :token_digest, unique: true
    create_table :guide_positions do |t|
      t.references :guide, null: false, foreign_key: true, index: { unique: true }
      t.float :latitude, null: false
      t.float :longitude, null: false
      t.float :accuracy, null: false
      t.float :speed_kmh
      t.datetime :captured_at, null: false
      t.datetime :received_at, null: false
      t.timestamps
    end
    create_table :guide_speed_alerts do |t|
      t.references :guide, null: false, foreign_key: true
      t.string :guide_name, null: false
      t.date :day, null: false
      t.datetime :first_at, null: false
      t.datetime :last_at, null: false
      t.float :peak_kmh, null: false
      t.datetime :ended_at
      t.datetime :acknowledged_at
      t.timestamps
    end
    add_index :guide_speed_alerts, [:day, :first_at]
    add_index :guide_speed_alerts, :guide_id, unique: true, where: 'ended_at IS NULL', name: 'one_open_speed_alert_per_guide'
  end
end
