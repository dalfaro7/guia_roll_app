class CreateVoiceChannels < ActiveRecord::Migration[8.1]
  def up
    create_table :voice_channels do |t|
      t.string :name, null: false
      t.string :room_key, null: false
      t.boolean :active, default: true, null: false
      t.timestamps
    end
    add_index :voice_channels, :room_key, unique: true
    create_table :voice_memberships do |t|
      t.references :mobile_account, null: false, foreign_key: true
      t.references :voice_channel, null: false, foreign_key: true
      t.timestamps
    end
    add_index :voice_memberships, [:mobile_account_id, :voice_channel_id], unique: true, name: 'unique_voice_membership'
    execute "INSERT INTO voice_channels (name, room_key, active, created_at, updated_at) VALUES ('Arenal Rafting Team', 'guide-team-general', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP), ('Abccanyoning Team', 'abccanyoning-team', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"
    # Conserva el acceso al antiguo canal general; ABC requiere asignacion explicita.
    execute "INSERT INTO voice_memberships (mobile_account_id, voice_channel_id, created_at, updated_at) SELECT mobile_accounts.id, voice_channels.id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP FROM mobile_accounts CROSS JOIN voice_channels WHERE voice_channels.room_key = 'guide-team-general'"
  end
  def down
    drop_table :voice_memberships
    drop_table :voice_channels
  end
end
