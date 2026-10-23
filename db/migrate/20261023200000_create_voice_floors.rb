class CreateVoiceFloors < ActiveRecord::Migration[8.1]
  def change
    create_table :voice_floors do |t|
      t.string :room_key, null: false
      t.string :holder_identity
      t.string :holder_name
      t.datetime :expires_at
      t.string :lease_id
      t.timestamps
    end
    add_index :voice_floors, :room_key, unique: true
  end
end
