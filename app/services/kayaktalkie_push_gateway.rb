require 'net/http'
class KayaktalkiePushGateway
  def self.enabled? = ENV['KAYAK_REPORT_PUSH_ENABLED'] == 'true'
  def self.post(endpoint, payload)
    uri=URI("https://exp.host/--/api/v2/push/#{endpoint}")
    request=Net::HTTP::Post.new(uri)
    request['Content-Type']='application/json'
    request['Authorization']="Bearer #{ENV['EXPO_ACCESS_TOKEN']}" if ENV['EXPO_ACCESS_TOKEN'].present?
    request.body=JSON.generate(payload)
    response=Net::HTTP.start(uri.host,uri.port,use_ssl:true,open_timeout:5,read_timeout:10) { |http|http.request(request) }
    raise 'No se pudo enviar la notificación al proveedor.' unless response.is_a?(Net::HTTPSuccess)
    JSON.parse(response.body).fetch('data')
  end
  def self.send_report(session, report)
    post('send', {to:session.expo_push_token,title:'KayakTalkie · nuevo reporte',body:'Hay un evento nuevo en uno de tus equipos. Toca para verlo.',
      channelId:'field-reports',priority:'high',ttl:[(report.expires_at-Time.current).to_i,0].max,
      data:{type:'field_report',reportId:report.id,accountId:session.kayaktalkie_account_id,expiresAt:report.expires_at.iso8601}})
  end
end
