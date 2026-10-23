require 'test_helper'

class OfficeAccountsTest < ActionDispatch::IntegrationTest
  setup do
    @office = MobileAccount.create!(account_type: 'office', name: 'Oficina prueba', phone: '87771234', location_enabled: false, password: 'Office-test-123456')
    @office.voice_channels << VoiceChannel.find_by!(room_key: VoiceFloor::ROOM)
    @admin = User.create!(name: 'Admin cuentas', email: 'office-admin@example.test', password: 'Office-test-123456', role: :admin)
  end
  test 'independent office account logs in and can only use voice' do
    assert_nil @office.guide_id
    post '/api/login', params: { phone: '87771234', password: 'Office-test-123456' }, as: :json
    assert_response :success
    assert_equal 'Oficina prueba', response.parsed_body.dig('user', 'name')
    assert_equal false, response.parsed_body.dig('user', 'capabilities', 'share_location')
    headers = { 'Authorization' => "Bearer #{response.parsed_body['token']}" }
    get '/api/account', headers: headers
    assert_response :success
    get '/api/voice/status', headers: headers
    assert_response :success
    assert_no_difference ['GuidePosition.count', 'GuideSpeedAlert.count'] do
      post '/api/location', params: {latitude: 10.4, longitude: -84.6}, headers: headers, as: :json
      assert_response :forbidden
    end
    %w[/api/users /api/alerts /api/reports/speed].each do |path|
      get path, headers: headers
      assert_response :unauthorized
    end
    @office.update!(active: false)
    get '/api/voice/status', headers: headers
    assert_response :unauthorized
  end
  test 'office requires name and cannot have guide or location permission' do
    @office.name = ''
    assert_not @office.valid?
    @office.name = 'Oficina'
    @office.location_enabled = true
    assert_not @office.valid?
    assert_raises(ActiveRecord::StatementInvalid) do
      MobileAccount.transaction(requires_new: true) { @office.update_columns(location_enabled: true) }
    end
  end
  test 'office web login and voice join accept valid CSRF and use office identity' do
    previous_protection = ActionController::Base.allow_forgery_protection
    previous_env = ENV.values_at('LIVEKIT_URL', 'LIVEKIT_API_KEY', 'LIVEKIT_API_SECRET')
    begin
      ActionController::Base.allow_forgery_protection = true
      ENV['LIVEKIT_URL'] = 'ws://127.0.0.1:7880'
      ENV['LIVEKIT_API_KEY'] = 'local-test'
      ENV['LIVEKIT_API_SECRET'] = 'local-test-only-secret'
      get '/kayaktalkie/login'
      csrf = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')['content']
      post '/kayaktalkie/login', params: {phone: '87771234', password: 'Office-test-123456'}, headers: {'X-CSRF-Token' => csrf}
      assert_redirected_to kayaktalkie_path
      get '/kayaktalkie'
      csrf = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')['content']
      post '/api/voice/join', headers: {'X-CSRF-Token' => csrf}, as: :json
      assert_response :success
      claims = JWT.decode(response.parsed_body['participantToken'], 'local-test-only-secret', true, algorithms: ['HS256']).first
      assert_equal 'Oficina prueba', claims['name']
      assert_match(/\Amobile-\d+\z/, claims['sub'])
      assert_equal false, claims.dig('video', 'canPublish')
      @office.update!(active: false)
      get '/kayaktalkie'
      assert_redirected_to kayaktalkie_login_path
    ensure
      ActionController::Base.allow_forgery_protection = previous_protection
      %w[LIVEKIT_URL LIVEKIT_API_KEY LIVEKIT_API_SECRET].zip(previous_env).each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end
  end
  test 'administrator creates office account without guide or email and map excludes it' do
    sign_in @admin
    assert_difference 'MobileAccount.count', 1 do
      post '/tracking/accounts', params: {mobile_account: {account_type: 'office', name: 'Recepción', phone: '87775678', password: 'Office-test-123456', location_enabled: '1'}}
    end
    assert_redirected_to tracking_accounts_path
    account = MobileAccount.find_by!(phone: '+50687775678')
    assert_nil account.guide_id
    assert_nil account.email
    assert_not account.can_share_location?
    get '/api/users'
    assert_response :success
    assert_not response.parsed_body.any? { |row| row['phone'] == account.phone }
    get '/tracking/accounts'
    assert_select 'td', text: 'Recepción'
  end
  test 'office browser session only opens the isolated voice screen and expires' do
    get '/kayaktalkie/login'
    assert_response :success
    assert_select 'input[type=tel]'
    post '/kayaktalkie/login', params: {phone: '87771234', password: 'Office-test-123456'}
    assert_redirected_to kayaktalkie_path
    get '/kayaktalkie'
    assert_response :success
    assert_select '#voiceJoin'
    assert_select 'a[href="/tracking"]', count: 0
    assert_select '#reportDialog', count: 0
    get '/api/voice/status'
    assert_response :success
    # Cookie-authenticated writes must include CSRF protection.
    post '/api/voice/claim', as: :json
    assert_response :forbidden
    %w[/tracking /tracking/accounts /tracking/voice].each do |path|
      get path
      assert_redirected_to new_user_session_path
    end
    %w[/api/users /api/alerts /api/reports/speed].each do |path|
      get path
      assert_response :unauthorized
    end
    post '/kayaktalkie/logout'
    assert_redirected_to kayaktalkie_login_path
    get '/api/voice/status'
    assert_response :unauthorized
  end
  test 'guide accounts cannot use office web login and disabled GPS is enforced' do
    guide = Guide.create!(name: 'Guía sin GPS', active: true, priority: 1)
    account = MobileAccount.create!(guide: guide, phone: '87779999', location_enabled: false, password: 'Office-test-123456')
    post '/kayaktalkie/login', params: {phone: '87779999', password: 'Office-test-123456'}
    assert_response :unprocessable_entity
    headers = {'Authorization' => "Bearer #{MobileSession.issue!(account)}"}
    post '/api/location', headers: headers, params: {}, as: :json
    assert_response :forbidden
    guide.update!(active: false)
    get '/api/voice/status', headers: headers
    assert_response :unauthorized
  end
end
