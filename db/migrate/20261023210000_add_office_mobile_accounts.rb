class AddOfficeMobileAccounts < ActiveRecord::Migration[8.1]
  def change
    change_column_null :mobile_accounts, :guide_id, true
    add_column :mobile_accounts, :account_type, :string, default: 'guide', null: false
    add_column :mobile_accounts, :name, :string
    add_column :mobile_accounts, :location_enabled, :boolean, default: true, null: false
    add_check_constraint :mobile_accounts,
      "(account_type = 'guide' AND guide_id IS NOT NULL) OR (account_type = 'office' AND guide_id IS NULL AND name IS NOT NULL AND length(trim(name)) > 0 AND location_enabled = FALSE)",
      name: 'mobile_account_identity'
  end
end
