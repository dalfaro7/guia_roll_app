class AddUniqueIndexToWorkDaysDate < ActiveRecord::Migration[8.1]
  def change
    add_index :work_days, :date, unique: true
  end
end
