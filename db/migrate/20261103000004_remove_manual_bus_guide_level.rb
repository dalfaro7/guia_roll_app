class RemoveManualBusGuideLevel < ActiveRecord::Migration[8.1]
  def change
    remove_column :guides, :pay_level_two, :boolean, default: false, null: false
    remove_column :compensation_assignments, :pay_level_two_snapshot, :boolean
  end
end
