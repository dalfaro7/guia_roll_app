class AllowOptionalCreditsOnOfficeEmployeeDays < ActiveRecord::Migration[8.1]
  def change
    change_column_null :office_employee_days, :office_day_credit_id, true
    change_column_null :office_employee_days, :office_vacation_credit_id, true
  end
end
