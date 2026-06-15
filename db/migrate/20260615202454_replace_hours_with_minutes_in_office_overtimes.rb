class ReplaceHoursWithMinutesInOfficeOvertimes < ActiveRecord::Migration[7.1]
  def change
    remove_column :office_overtimes, :hours, :decimal
    add_column :office_overtimes, :minutes, :integer, default: 0, null: false
  end
end
