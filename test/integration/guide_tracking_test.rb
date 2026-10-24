require 'test_helper'
class GuideTrackingTest < ActionDispatch::IntegrationTest
  setup do
    @guide = Guide.create!(name: 'GPS prueba', priority: 1, active: true)
    @account = KayaktalkieAccount.create!(name: @guide.name, location_enabled: true, phone: '8888 1234', password: 'Test-location-123456')
    @admin = KayaktalkieAccount.create!(name: 'GPS Admin', phone: '89990126', password: 'Test-admin-123456', role: 'admin')
    @operator = User.create!(name: 'GPS Operador', email: 'gpsoperator@test.example', password: 'Test-admin-123456', role: :operador)
  end
  test 'mobile contract and admin access remain separate' do
    post '/api/login', params: {phone: @account.phone, password: 'Test-location-123456'}, as: :json
    assert_response :success
    token = response.parsed_body['token']
    assert_equal 'GPS prueba', response.parsed_body.dig('user','name')
    headers = {'Authorization' => "Bearer #{token}"}
    get '/api/users', headers: headers
    assert_response :forbidden
    at = Time.current.to_f * 1000
    data = {latitude: 10.4, longitude: -84.6, accuracy: 10, capturedAt: at, speedMps: 25}
    post '/api/location', params: data, headers: headers, as: :json
    assert_response :success
    assert_equal 0, KayaktalkieSpeedAlert.where(kayaktalkie_account: @account).count
    post '/api/location', params: data.merge(capturedAt: at+1, speedMps: 30), headers: headers, as: :json
    assert_response :success
    assert_equal 108, KayaktalkiePosition.find_by!(kayaktalkie_account: @account).speed_kmh
    assert_equal 1, KayaktalkieSpeedAlert.where(kayaktalkie_account: @account).count
    post '/api/location', params: data.merge(speedMps: 40), headers: headers, as: :json
    assert_equal 108, KayaktalkiePosition.find_by!(kayaktalkie_account: @account).speed_kmh
    sign_in @operator
    get '/api/alerts'
    assert_response :unauthorized
    get '/tracking'
    assert_redirected_to kayaktalkie_login_path
    sign_out @operator
    post '/kayaktalkie/login', params: {phone: @admin.phone,password: 'Test-admin-123456'}
    get '/api/users'
    assert_response :success
    assert_equal @guide.name, response.parsed_body.first['name']
    get '/api/alerts'
    assert_equal 1, response.parsed_body['unreadCount']
    post '/api/alerts/ack', params: {id: KayaktalkieSpeedAlert.last.id}, as: :json
    assert_response :forbidden
    assert_nil KayaktalkieSpeedAlert.last.acknowledged_at
    get '/tracking'
    assert_response :success
    assert_select '#reportDialog'
    get '/tracking/accounts'
    assert_response :success
    get '/api/reports/speed', params: {date: '2026-02-30'}
    assert_response :bad_request
    post '/api/logout', headers: headers, as: :json
    assert_response :success
    post '/api/location', params: data, headers: headers, as: :json
    assert_response :unauthorized
  end
  test 'phone is the login without email and equivalent formats cannot duplicate' do
    assert_equal '+50688881234', @account.phone
    assert_nil @account.email
    ['8888 1234', '+506 8888-1234', '50688881234'].each do |phone|
      post '/api/login', params: {phone: phone, password: 'Test-location-123456'}, as: :json
      assert_response :success
    end
    # Transitional Android clients submit their username in the old email JSON key.
    post '/api/login', params: {email: '88881234', password: 'Test-location-123456'}, as: :json
    assert_response :success
    post '/api/login', params: {phone: '88881234', password: 'incorrecta'}, as: :json
    assert_response :unauthorized
    assert_nil KayaktalkieAccount.normalize_phone('abc88881234')
    assert_nil KayaktalkieAccount.normalize_phone('123')
    other = Guide.create!(name: 'Otro GPS', priority: 1, active: true)
    duplicate = KayaktalkieAccount.new(name: other.name, phone: '+50688881234', password: 'Test-location-123456')
    assert_not duplicate.valid?
    assert duplicate.errors[:phone].present?
    post '/kayaktalkie/login', params: {phone: @admin.phone,password: 'Test-admin-123456'}
    get '/tracking/accounts'
    assert_select 'input[type=tel]'
    assert_select 'input[type=email][required]', count: 0
  end
  test 'episodes split across Costa Rica midnight and gaps and keep acknowledgements' do
    time = Time.zone.parse('2026-10-23 23:59:59')
    KayaktalkieSpeedAlert.record!(@account, time, 100)
    KayaktalkieSpeedAlert.record!(@account, time+2, 101)
    KayaktalkieSpeedAlert.record!(@account, time+183, 102)
    assert_equal 3, KayaktalkieSpeedAlert.where(kayaktalkie_account: @account).count
    alert = KayaktalkieSpeedAlert.where(kayaktalkie_account: @account, ended_at: nil).first!
    alert.update!(acknowledged_at: Time.current)
    KayaktalkieSpeedAlert.record!(@account, time+184, 110)
    assert_equal 110, alert.reload.peak_kmh
    assert alert.acknowledged_at
  end
  test 'five minute estimate persists through ingestion without exposing raw samples' do
    started = 5.minutes.ago
    (0..10).each do |i|
      KayaktalkieTrackingIngest.call(@account, {'latitude'=>0.0,'longitude'=>i*0.001,'accuracy'=>5.0,'capturedAt'=>(started+i*30).to_f*1000,'speedMps'=>30.0})
    end
    position=KayaktalkiePosition.find_by!(kayaktalkie_account:@account)
    assert_equal 11,position.speed_samples.size
    assert_equal 'ready',position.speed_estimate['status']
    assert_in_delta 13.3434,position.speed_estimate['kmh'],0.001
    assert_equal 108,position.speed_kmh
    assert_equal 108,KayaktalkieSpeedAlert.where(kayaktalkie_account:@account).last.peak_kmh
    post '/kayaktalkie/login',params:{phone:@admin.phone,password:'Test-admin-123456'}
    get '/api/users'
    item=response.parsed_body.find { |u| u['id']==@account.id }
    assert_equal 'ready',item.dig('speed_estimate','status')
    assert_not item.key?('speed_samples')
    KayaktalkieTrackingIngest.call(@account, {'latitude'=>0.0,'longitude'=>0.011,'accuracy'=>100.0,'capturedAt'=>(started+310).to_f*1000})
    assert_in_delta 13.3434, position.reload.speed_estimate.dig('last_valid','kmh'), 0.001
    team=KayaktalkieTeam.first!
    @account.kayaktalkie_team_memberships.create!(kayaktalkie_team:team)
    KayaktalkieTrackingIngest.call(@account, {'latitude'=>0.0,'longitude'=>0.011,'accuracy'=>5.0,'capturedAt'=>(started+330).to_f*1000})
    assert_equal 1,position.reload.speed_samples.size
    assert_equal 'warming_up',position.speed_estimate['status']
    assert_nil position.speed_estimate['last_valid']
  end

end
