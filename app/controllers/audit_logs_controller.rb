class AuditLogsController < ApplicationController
  def index
    @audit_logs = AuditLog
                    .includes(:user, :work_day)
                    .recent
                    .limit(500)
  end
end
