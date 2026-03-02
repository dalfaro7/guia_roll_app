class SetDefaultStatusInWorkDays < ActiveRecord::Migration[8.1]
  def change
  change_column_default :work_days, :status, 0
  end
end
