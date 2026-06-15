class AddDepartmentToOfficeEmployees < ActiveRecord::Migration[8.1]
  def change
    add_column :office_employees, :department, :string
  end
end
