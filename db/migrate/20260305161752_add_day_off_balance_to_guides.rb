class AddDayOffBalanceToGuides < ActiveRecord::Migration[8.1]
  def change
    add_column :guides, :day_off_balance, :integer, default: 0, null: false
    add_column :guides, :day_off_balance_updated_at, :datetime
  end
end
