class AddDeletedAtToKayaktalkieAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :kayaktalkie_accounts, :deleted_at, :datetime
    add_index :kayaktalkie_accounts, :deleted_at
  end
end
