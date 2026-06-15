class AddRestrictionsToOfficeEmployees < ActiveRecord::Migration[8.1]
  def change
    add_column :office_employees, :restricted_day_off_weekday, :integer
  end
end
