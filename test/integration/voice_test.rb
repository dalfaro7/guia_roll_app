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
    account = MobileAccount.create!(guide: guide, phone: '88889999', password: 'Voice-test-123456')
    account.voice_channels << VoiceChannel.find_by!(room_key: VoiceFloor::ROOM)
    @token = MobileSession.issue!(account)
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
    assert_response :success
    assert_select '#voiceJoin'
    user.update!(role: :operador)
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
