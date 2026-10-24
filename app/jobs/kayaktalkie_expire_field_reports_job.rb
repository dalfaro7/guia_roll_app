class KayaktalkieExpireFieldReportsJob < ApplicationJob
  queue_as :default
  def perform
    KayaktalkieFieldReport.expired.find_each do |report|
      report.with_lock do
        next if report.expires_at > Time.current
        report.destroy!
      end
    end
  end
end
