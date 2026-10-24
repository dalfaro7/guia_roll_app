class SeparateKayaktalkieAccounts < ActiveRecord::Migration[8.1]
  def up
    # Refuse to discard or guess ownership of historical tracking data.
    %w[guide_positions guide_speed_alerts].each do |table|
      count = select_value("SELECT COUNT(*) FROM #{table} t LEFT JOIN mobile_accounts a ON a.guide_id=t.guide_id WHERE a.id IS NULL").to_i
      raise "#{table}: #{count} records without a matching account; reconcile before migration" if count.positive?
    end
    rename_table :mobile_accounts, :kayaktalkie_accounts
    rename_table :mobile_sessions, :kayaktalkie_sessions
    rename_column :kayaktalkie_sessions, :mobile_account_id, :kayaktalkie_account_id
    rename_column :voice_memberships, :mobile_account_id, :kayaktalkie_account_id
    remove_check_constraint :kayaktalkie_accounts, name: 'mobile_account_identity'
    execute "UPDATE kayaktalkie_accounts a SET name=g.name FROM guides g WHERE a.guide_id=g.id"
    execute "UPDATE kayaktalkie_accounts a SET active=FALSE FROM guides g WHERE a.guide_id=g.id AND g.active=FALSE"
    change_column_null :kayaktalkie_accounts, :name, false
    add_column :kayaktalkie_accounts, :role, :string, default: 'staff', null: false
    add_check_constraint :kayaktalkie_accounts, "role IN ('admin','operator','staff')", name: 'kayaktalkie_role'
    add_check_constraint :kayaktalkie_accounts, "length(trim(name)) > 0", name: 'kayaktalkie_name'
    create_table :kayaktalkie_teams do |t|
      t.string :name, null: false
      t.timestamps
    end
    create_table :kayaktalkie_team_memberships do |t|
      t.references :kayaktalkie_account, null: false, foreign_key: true
      t.references :kayaktalkie_team, null: false, foreign_key: true
      t.timestamps
    end
    add_index :kayaktalkie_team_memberships, [:kayaktalkie_account_id,:kayaktalkie_team_id], unique: true, name: 'unique_kayaktalkie_team_member'
    add_reference :voice_channels, :kayaktalkie_team, foreign_key: true
    # One isolated team per existing channel; no implicit cross-channel access.
    select_all('SELECT id,name FROM voice_channels ORDER BY id').each do |c|
      team_id=select_value("INSERT INTO kayaktalkie_teams(name,created_at,updated_at) VALUES(#{quote(c['name'])},CURRENT_TIMESTAMP,CURRENT_TIMESTAMP) RETURNING id")
      execute "UPDATE voice_channels SET kayaktalkie_team_id=#{team_id.to_i} WHERE id=#{c['id'].to_i}"
      execute "INSERT INTO kayaktalkie_team_memberships(kayaktalkie_account_id,kayaktalkie_team_id,created_at,updated_at) SELECT kayaktalkie_account_id,#{team_id.to_i},CURRENT_TIMESTAMP,CURRENT_TIMESTAMP FROM voice_memberships WHERE voice_channel_id=#{c['id'].to_i}"
    end
    change_column_null :voice_channels, :kayaktalkie_team_id, false
    {guide_positions: :kayaktalkie_positions, guide_speed_alerts: :kayaktalkie_speed_alerts}.each do |old,new_table|
      rename_table old,new_table
      add_reference new_table, :kayaktalkie_account, foreign_key: true
      execute "UPDATE #{new_table} t SET kayaktalkie_account_id=a.id FROM kayaktalkie_accounts a WHERE a.guide_id=t.guide_id"
      change_column_null new_table, :kayaktalkie_account_id, false
      add_column new_table, :team_ids_at_capture, :bigint, array: true, default: [], null: false
      execute "UPDATE #{new_table} t SET team_ids_at_capture=ARRAY(SELECT m.kayaktalkie_team_id FROM kayaktalkie_team_memberships m WHERE m.kayaktalkie_account_id=t.kayaktalkie_account_id)"
      remove_reference new_table, :guide, foreign_key: true
    end
    add_index :kayaktalkie_positions, :kayaktalkie_account_id, unique: true, name: 'one_kayaktalkie_position'
    add_index :kayaktalkie_speed_alerts, :kayaktalkie_account_id, unique: true, where: 'ended_at IS NULL', name: 'one_open_kayaktalkie_speed_alert'
    rename_column :kayaktalkie_speed_alerts, :guide_name, :account_name
    remove_reference :kayaktalkie_accounts, :guide, foreign_key: true
    remove_column :kayaktalkie_accounts, :account_type
    remove_column :kayaktalkie_accounts, :email
  end
  def down
    raise ActiveRecord::IrreversibleMigration, 'Independent accounts cannot safely become guides. Restore the verified backup instead.'
  end
end
