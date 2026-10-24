require 'test_helper'

class VoiceTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  def with_transport(name, implementation)
    original = VoiceTransport.method(name)
    VoiceTransport.define_singleton_method(name, implementation.respond_to?(:call) ? implementation : -> { implementation })
    yield
  ensure
    VoiceTransport.define_singleton_method(name, original)
  end
  setup do
    guide = Guide.create!(name: 'Guía voz', active: true, priority: 1)
    account = KayaktalkieAccount.create!(name: guide.name, phone: '88889999', password: 'Voice-test-123456')
    account.kayaktalkie_teams << VoiceChannel.find_by!(room_key: VoiceFloor::ROOM).kayaktalkie_team
    account.voice_channels << VoiceChannel.find_by!(room_key: VoiceFloor::ROOM)
    @token = KayaktalkieSession.issue!(account)
    @headers = {'Authorization' => "Bearer #{@token}"}
  end
  test 'voice requires authenticated participation and reports missing infrastructure' do
    post '/api/voice/join', as: :json
    assert_response :unauthorized
    with_transport(:configured?, false) do
      post '/api/voice/join', headers: @headers, as: :json
      assert_response :service_unavailable
    end
    get '/api/voice/status', headers: @headers
    assert_response :success
    assert_nil response.parsed_body['speaker']
  end
  test 'single speaker lease and expiration revoke publish permission' do
    calls = []
    with_transport(:permission, ->(identity, publish, **options) { calls << [identity,publish] }) do
      assert_enqueued_with(job: VoiceReleaseJob) do
        post '/api/voice/claim', headers: @headers, as: :json
        assert_response :success
      end
      lease = response.parsed_body['lease']
      post '/api/voice/claim', headers: @headers, as: :json
      assert_response :conflict
      post '/api/voice/release', params: {lease: 'wrong'}, headers: @headers, as: :json
      assert_equal false, response.parsed_body['ok']
      assert VoiceFloor.general.holder_identity
      post '/api/voice/release', params: {lease: lease}, headers: @headers, as: :json
      assert_equal true, response.parsed_body['ok']
      assert_nil VoiceFloor.general.holder_identity
      assert_equal [true,false], calls.map(&:last)
      turn = VoiceTurn.claim('test-other', 'Otro')
      floor = VoiceFloor.general
      floor.update!(expires_at: 1.second.ago)
      VoiceReleaseJob.perform_now(floor.id, 'stale-lease')
      assert floor.reload.holder_identity
      VoiceReleaseJob.perform_now(floor.id, turn[:lease])
      assert_nil floor.reload.holder_identity
      assert_equal ['test-other',false], calls.last
    end
  end
  test 'uncertain network grant keeps its reservation until recovery' do
    with_transport(:permission, ->(*) { raise VoiceTransport::Unavailable, 'Prueba sin red' }) do
      post '/api/voice/claim', headers: @headers, as: :json
      assert_response :service_unavailable
      assert VoiceFloor.general.holder_identity
      post '/api/voice/claim', headers: @headers, as: :json
      assert_response :conflict
    end
  end
  test 'administrator can open the walkie screen but operator cannot join' do
    user = User.create!(name: 'Admin voz', email: 'voice-admin@example.test', password: 'Voice-admin-123456', role: :admin)
    sign_in user
    get '/tracking/voice'
    assert_redirected_to kayaktalkie_login_path
    admin = KayaktalkieAccount.create!(name: 'Independent admin', phone: '89990123', role: 'admin', password: 'Voice-admin-123456')
    post '/kayaktalkie/login', params: {phone: admin.phone, password: 'Voice-admin-123456'}
    get '/tracking/voice'
    assert_redirected_to tracking_path(anchor: 'voicePanel')
    follow_redirect!
    assert_response :success
    assert_select '#map'
    assert_select 'aside #voiceJoin', count: 0
    assert_select 'aside #voiceMute', count: 1
    assert_select '#voiceChannel option[value=""]', count: 1
    assert_select 'aside #voiceTalk[disabled]', count: 1
    assert_select 'a[href="/tracking/voice"]', count: 0
    admin.update!(active: false)
    post '/api/voice/join', as: :json
    assert_response :unauthorized
  end
  test 'join token allows listening without microphone or data publishing' do
    old = ENV.values_at('LIVEKIT_URL','LIVEKIT_API_KEY','LIVEKIT_API_SECRET')
    begin
      ENV['LIVEKIT_URL']='wss://voice.test'; ENV['LIVEKIT_API_KEY']='testkey'; ENV['LIVEKIT_API_SECRET']='test-secret-only-not-production'
      post '/api/voice/join', headers: @headers, as: :json
      assert_response :success
      claims = JWT.decode(response.parsed_body['participantToken'], ENV['LIVEKIT_API_SECRET'], true, algorithms: ['HS256']).first
      assert_equal true, claims.dig('video','canSubscribe')
      assert_equal false, claims.dig('video','canPublish')
      assert_equal false, claims.dig('video','canPublishData')
      assert_equal VoiceFloor::ROOM, claims.dig('video','room')
    ensure
      %w[LIVEKIT_URL LIVEKIT_API_KEY LIVEKIT_API_SECRET].zip(old).each { |k,v| v.nil? ? ENV.delete(k) : ENV[k]=v }
    end
  end
end
