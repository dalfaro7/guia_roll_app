class AddOfficeVacationCreditToOfficeEmployeeDays < ActiveRecord::Migration[8.1]
  def change
    add_reference :office_employee_days,
                  :office_vacation_credit,
                  null: true,
                  foreign_key: true
  end
end
