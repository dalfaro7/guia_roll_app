class SetDefaultWorkedDaysOnMonthlyBalances < ActiveRecord::Migration[8.0]
  def change
    change_column_default :monthly_balances, :worked_days, 0
    change_column_null :monthly_balances, :worked_days, false
  end
end