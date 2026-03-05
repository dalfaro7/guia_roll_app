class AddDayOffConsumedToGuideDays < ActiveRecord::Migration[8.1]
  def change
    add_column :guide_days, :day_off_consumed, :boolean, default: false, null: false
  end
end
