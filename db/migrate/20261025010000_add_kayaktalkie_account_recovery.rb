class AddKayaktalkieAccountRecovery < ActiveRecord::Migration[8.1]
  def change
    add_column :kayaktalkie_accounts, :email, :string
    add_index :kayaktalkie_accounts, 'lower(email)', unique: true, where: 'email IS NOT NULL', name: 'unique_kayak_email'
    add_reference :kayaktalkie_accounts, :created_by, foreign_key: {to_table: :kayaktalkie_accounts}
    add_column :kayaktalkie_accounts, :reset_password_digest, :string
    add_column :kayaktalkie_accounts, :reset_password_sent_at, :datetime
    add_index :kayaktalkie_accounts, :reset_password_digest, unique: true
  end
end
