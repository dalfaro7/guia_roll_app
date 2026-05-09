class AllowNullWorkDayIdOnAuditLogs < ActiveRecord::Migration[8.1]
  def change
    change_column_null :audit_logs, :work_day_id, true
  end
end