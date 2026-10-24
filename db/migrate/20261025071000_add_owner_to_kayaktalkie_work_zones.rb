class AddOwnerToKayaktalkieWorkZones < ActiveRecord::Migration[8.1]
  def change
    add_reference :kayaktalkie_work_zones, :operator, null: false, foreign_key: {to_table: :kayaktalkie_accounts}
  end
end
