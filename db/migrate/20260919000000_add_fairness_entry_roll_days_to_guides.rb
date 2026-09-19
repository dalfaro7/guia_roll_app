class AddFairnessEntryRollDaysToGuides < ActiveRecord::Migration[8.1]
  def change
    add_column :guides, :fairness_entry_roll_days, :integer,
               default: 0, null: false
  end
end
