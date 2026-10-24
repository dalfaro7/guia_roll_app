class KayaktalkieRecoverReportNotificationsJob < ApplicationJob
  queue_as :default
  def perform
    return unless KayaktalkiePushGateway.enabled?
    KayaktalkieFieldReport.unexpired.where(resolved_at:nil).find_each do |report|
      KayaktalkieNotifyFieldReportJob.perform_later(report.id)
    end
  end
end
