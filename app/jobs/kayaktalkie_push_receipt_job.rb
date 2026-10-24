class KayaktalkiePushReceiptJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 4
  def perform(delivery_id)
    return unless KayaktalkiePushGateway.enabled?
    delivery=KayaktalkieReportDelivery.find_by(id:delivery_id,status:'accepted')
    return unless delivery
    result=KayaktalkiePushGateway.post('getReceipts',{ids:[delivery.ticket_id]})[delivery.ticket_id]
    raise 'Acuse de notificación pendiente.' unless result
    if result['status']=='ok'
      delivery.update!(status:'delivered_to_provider')
    else
      sent_at=delivery.updated_at
      delivery.update!(status:'failed')
      if result.dig('details','error')=='DeviceNotRegistered'
        KayaktalkieSession.where(id:delivery.kayaktalkie_session_id).where('updated_at <= ?',sent_at).update_all(expo_push_token:nil)
      end
    end
  end
end
