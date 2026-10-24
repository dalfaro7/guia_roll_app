class KayaktalkieNotifyFieldReportJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 5
  def perform(report_id)
    return unless KayaktalkiePushGateway.enabled?
    report=KayaktalkieFieldReport.unexpired.find_by(id:report_id,resolved_at:nil)
    return unless report
    team_accounts=KayaktalkieTeamMembership.where(kayaktalkie_team_id:report.kayaktalkie_team_id).select(:kayaktalkie_account_id)
    accounts=KayaktalkieAccount.where(active:true).where(id:team_accounts).or(KayaktalkieAccount.where(active:true,role:'admin')).where.not(id:report.kayaktalkie_account_id)
    KayaktalkieSession.where(kayaktalkie_account_id:accounts.select(:id)).where('expires_at > ?',Time.current).where.not(expo_push_token:nil).find_each do |recipient|
      delivery=KayaktalkieReportDelivery.find_or_create_by!(kayaktalkie_field_report:report,kayaktalkie_session:recipient)
      delivery.with_lock do
        next unless delivery.status=='pending'
        recipient.reload
        account=recipient.kayaktalkie_account.reload
        next unless recipient.expires_at>Time.current && recipient.expo_push_token.present? && account.active? && (account.admin? || account.kayaktalkie_team_ids.include?(report.kayaktalkie_team_id))
        break if report.reload.resolved_at || report.expires_at<=Time.current
        result=KayaktalkiePushGateway.send_report(recipient,report)
        if result['status']=='ok'
          delivery.update!(status:'accepted',ticket_id:result.fetch('id'))
          KayaktalkiePushReceiptJob.set(wait:15.minutes).perform_later(delivery.id)
        elsif result.dig('details','error')=='DeviceNotRegistered'
          recipient.update!(expo_push_token:nil);delivery.update!(status:'unregistered')
        else
          raise 'Proveedor rechazó la notificación; revisar configuración.'
        end
      end
    end
  end
end
