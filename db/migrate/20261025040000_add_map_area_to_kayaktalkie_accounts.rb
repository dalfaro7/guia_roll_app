class AddMapAreaToKayaktalkieAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :kayaktalkie_accounts, :map_area, :jsonb
  end
end
