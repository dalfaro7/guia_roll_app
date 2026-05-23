class AuditLogsController < ApplicationController

  #before_action :require_admin!
  def index
    @audit_logs = AuditLog
                    .includes(:user, :work_day)
                    .recent
                    .limit(500)
  end
end
