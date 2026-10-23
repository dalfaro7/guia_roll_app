require 'test_helper'
class GuideTrackingTest < ActionDispatch::IntegrationTest
  setup do
    @guide = Guide.create!(name: 'GPS prueba', priority: 1, active: true)
    @account = MobileAccount.create!(guide: @guide, phone: '8888 1234', password: 'Test-location-123456')
    @admin = User.create!(name: 'GPS Admin', email: 'gpsadmin@test.example', password: 'Test-admin-123456', role: :admin)
    @operator = User.create!(name: 'GPS Operador', email: 'gpsoperator@test.example', password: 'Test-admin-123456', role: :operador)
  end
  test 'mobile contract and admin access remain separate' do
    post '/api/login', params: {phone: @account.phone, password: 'Test-location-123456'}, as: :json
    assert_response :success
    token = response.parsed_body['token']
    assert_equal 'GPS prueba', response.parsed_body.dig('user','name')
    headers = {'Authorization' => "Bearer #{token}"}
    get '/api/users', headers: headers
    assert_response :unauthorized
    at = Time.current.to_f * 1000
    data = {latitude: 10.4, longitude: -84.6, accuracy: 10, capturedAt: at, speedMps: 25}
    post '/api/location', params: data, headers: headers, as: :json
    assert_response :success
    assert_equal 0, GuideSpeedAlert.where(guide: @guide).count
    post '/api/location', params: data.merge(capturedAt: at+1, speedMps: 30), headers: headers, as: :json
    assert_response :success
    assert_equal 108, GuidePosition.find_by!(guide: @guide).speed_kmh
    assert_equal 1, GuideSpeedAlert.where(guide: @guide).count
    post '/api/location', params: data.merge(speedMps: 40), headers: headers, as: :json
    assert_equal 108, GuidePosition.find_by!(guide: @guide).speed_kmh
    sign_in @operator
    get '/api/alerts'
    assert_response :forbidden
    get '/tracking'
    assert_redirected_to root_path
    sign_out @operator
    sign_in @admin
    get '/api/users'
    assert_response :success
    assert_equal @guide.name, response.parsed_body.first['name']
    get '/api/alerts'
    assert_equal 1, response.parsed_body['unreadCount']
    post '/api/alerts/ack', params: {id: GuideSpeedAlert.last.id}, as: :json
    assert_response :forbidden
    assert_nil GuideSpeedAlert.last.acknowledged_at
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
    assert_nil MobileAccount.normalize_phone('abc88881234')
    assert_nil MobileAccount.normalize_phone('123')
    other = Guide.create!(name: 'Otro GPS', priority: 1, active: true)
    duplicate = MobileAccount.new(guide: other, phone: '+50688881234', password: 'Test-location-123456')
    assert_not duplicate.valid?
    assert duplicate.errors[:phone].present?
    sign_in @admin
    get '/tracking/accounts'
    assert_select 'input[type=tel]'
    assert_select 'input[type=email]', count: 0
  end
  test 'episodes split across Costa Rica midnight and gaps and keep acknowledgements' do
    time = Time.zone.parse('2026-10-23 23:59:59')
    GuideSpeedAlert.record!(@guide, time, 100)
    GuideSpeedAlert.record!(@guide, time+2, 101)
    GuideSpeedAlert.record!(@guide, time+183, 102)
    assert_equal 3, GuideSpeedAlert.where(guide: @guide).count
    alert = GuideSpeedAlert.where(guide: @guide, ended_at: nil).first!
    alert.update!(acknowledged_at: Time.current)
    GuideSpeedAlert.record!(@guide, time+184, 110)
    assert_equal 110, alert.reload.peak_kmh
    assert alert.acknowledged_at
  end
end
