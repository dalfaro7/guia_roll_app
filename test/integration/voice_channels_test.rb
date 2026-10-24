require 'test_helper'
class VoiceChannelsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  setup do
    @arenal = VoiceChannel.find_by!(room_key: VoiceFloor::ROOM)
    @abc = VoiceChannel.find_by!(room_key: 'abccanyoning-team')
    @account = KayaktalkieAccount.create!(name: 'Canales prueba', phone: '88882221', location_enabled: false, password: 'Channels-test-123456')
    @account.kayaktalkie_teams << @arenal.kayaktalkie_team
    @account.voice_channels << @arenal
    @headers = { 'Authorization' => "Bearer #{KayaktalkieSession.issue!(@account)}" }
  end
  def transport_stub(method, callable)
    previous = VoiceTransport.method(method)
    VoiceTransport.define_singleton_method(method, callable)
    yield
  ensure
    VoiceTransport.define_singleton_method(method, previous)
  end
  test 'channels list and JWT enforce membership on server including legacy APK' do
    get '/api/voice/channels', headers: @headers
    assert_equal [@arenal.id], response.parsed_body['channels'].map { |c| c['id'] }
    post '/api/voice/join', headers: @headers, params: {channel_id: @abc.id}, as: :json
    assert_response :forbidden
    post '/api/voice/claim', headers: @headers, params: {channel_id: @abc.id}, as: :json
    assert_response :forbidden
    transport_stub(:token, ->(identity, name, room:) { room }) do
      transport_stub(:url, -> { 'wss://example.test' }) do
        post '/api/voice/join', headers: @headers, as: :json
        assert_response :success
        assert_equal @arenal.room_key, response.parsed_body['participantToken']
        @account.kayaktalkie_teams << @abc.kayaktalkie_team
        @account.voice_channels << @abc
        post '/api/voice/join', headers: @headers, params: {channel_id: @abc.id}, as: :json
        assert_response :success
        assert_equal @abc.room_key, response.parsed_body['participantToken']
        @account.voice_memberships.destroy_all
        post '/api/voice/join', headers: @headers, as: :json
        assert_response :forbidden
      end
    end
  end
  test 'channels have independent floors and cross channel release cannot clear turn' do
    calls = []
    transport_stub(:permission, ->(identity, publish, room:) { calls << [identity, publish, room] }) do
      first = VoiceTurn.claim('mobile-a', 'A', channel: @arenal)
      second = VoiceTurn.claim('mobile-b', 'B', channel: @abc)
      assert_not VoiceTurn.release('mobile-a', first[:lease], channel: @abc)
      assert_equal 'mobile-b', VoiceFloor.for_channel(@abc).holder_identity
      floor = VoiceFloor.for_channel(@abc)
      floor.update!(expires_at: 1.second.ago)
      VoiceReleaseJob.perform_now(floor.id, second[:lease])
      assert_equal ['mobile-b', false, @abc.room_key], calls.last
      assert_equal 'mobile-a', VoiceFloor.for_channel(@arenal).holder_identity
    end
  end
  test 'only administrator can assign several channels and create channels' do
    post '/tracking/channels', params: {voice_channel: {name: 'Nuevo'}}
    assert_redirected_to kayaktalkie_login_path
    admin = KayaktalkieAccount.create!(name: 'Admin canales', phone: '89990124', password: 'Channels-test-123456', role: 'admin')
    post '/kayaktalkie/login', params: {phone: admin.phone, password: 'Channels-test-123456'}
    patch "/tracking/accounts/#{@account.id}/channels", params: {kayaktalkie_account: {name: @account.name}, team_ids: [@arenal.kayaktalkie_team_id,@abc.kayaktalkie_team_id], voice_channel_ids: [@arenal.id, @abc.id]}
    assert_redirected_to tracking_accounts_path
    assert_equal [@arenal.id, @abc.id].sort, @account.reload.voice_channel_ids.sort
    assert_enqueued_with(job: VoiceRevokeAccessJob, args: [@account.id, @abc.id]) do
      patch "/tracking/accounts/#{@account.id}/channels", params: {kayaktalkie_account: {name: @account.name}, team_ids: [@arenal.kayaktalkie_team_id,@abc.kayaktalkie_team_id], voice_channel_ids: [@arenal.id]}
    end
    patch "/tracking/accounts/#{@account.id}/channels", params: {kayaktalkie_account: {name: @account.name}, team_ids: [@arenal.kayaktalkie_team_id,@abc.kayaktalkie_team_id], voice_channel_ids: [999999]}
    assert_response :unprocessable_entity
    assert_equal [@arenal.id], @account.reload.voice_channel_ids
    assert_difference 'VoiceChannel.count', 1 do
      post '/tracking/channels', params: {voice_channel: {name: 'Equipo rescate', kayaktalkie_team_id: @arenal.kayaktalkie_team_id}}
    end
  end
  test 'revocation removes account sessions only from the revoked channel and skips restored access' do
    calls = []
    transport_stub(:disconnect, ->(identity, room:) { calls << [identity, room] }) do
      VoiceRevokeAccessJob.perform_now(@account.id, @arenal.id)
      assert_empty calls
      @account.voice_memberships.destroy_all
      VoiceRevokeAccessJob.perform_now(@account.id, @arenal.id)
      assert_equal 1, calls.length
      assert_equal @arenal.room_key, calls.first.last
    end
  end
  test 'deactivation disconnects identities even after sessions are destroyed' do
    identities = @account.kayaktalkie_sessions.map { |session| "mobile-#{session.id}" }
    assert identities.any?
    floor = VoiceFloor.for_channel(@arenal)
    floor.update!(holder_identity: identities.first, expires_at: 20.seconds.from_now)
    KayaktalkieAccess.assign!(@account, attributes:{active:false}, team_ids:[@arenal.kayaktalkie_team_id], channel_ids:[@arenal.id])
    assert_empty @account.reload.kayaktalkie_sessions
    calls = []
    transport_stub(:disconnect, ->(identity, room:) { calls << [identity, room] }) do
      VoiceRevokeAccessJob.perform_now(@account.id, @arenal.id, identities)
    end
    assert_equal identities.map { |identity| [identity, @arenal.room_key] }, calls
    assert_nil floor.reload.holder_identity
  end
  test 'disconnect calls the SDK with room-scoped keyword arguments' do
    fake = Object.new
    called = nil
    fake.define_singleton_method(:remove_with_cutoff) { |room:, identity:, cutoff:| called = [room, identity, cutoff] }
    old_url = VoiceTransport.method(:url)
    old_new = VoiceRoomClient.method(:new)
    original_env = ENV.values_at('LIVEKIT_API_KEY', 'LIVEKIT_API_SECRET')
    begin
      VoiceTransport.define_singleton_method(:url) { 'wss://example.test' }
      VoiceRoomClient.define_singleton_method(:new) { |*args, **kwargs| fake }
      ENV['LIVEKIT_API_KEY'] = 'test-key'
      ENV['LIVEKIT_API_SECRET'] = 'test-secret'
      VoiceTransport.disconnect('mobile-test', room: @abc.room_key)
      assert_equal [@abc.room_key, 'mobile-test'], called.first(2)
      assert_operator called.last, :>, Time.current.to_i
    ensure
      VoiceTransport.define_singleton_method(:url, old_url)
      VoiceRoomClient.define_singleton_method(:new, old_new)
      %w[LIVEKIT_API_KEY LIVEKIT_API_SECRET].zip(original_env).each { |key,value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end
  end
  test 'map shows simultaneous active turns in both channels only for administrator' do
    admin = KayaktalkieAccount.create!(name: 'Mapa canales', phone: '89990125', password: 'Channels-test-123456', role: 'admin')
    post '/kayaktalkie/login', params: {phone: admin.phone, password: 'Channels-test-123456'}
    [@arenal, @abc].each_with_index { |c,i| VoiceFloor.for_channel(c).update!(holder_identity: "mobile-#{i}", expires_at: 10.seconds.from_now) }
    get '/api/map/voice'
    assert_response :success
    assert_equal 2, response.parsed_body['speakers'].length
  end
end

class VoiceCutoffTest < ActiveSupport::TestCase
  test 'strict removal includes room limited admin grant and token cutoff in protobuf' do
    client = VoiceRoomClient.new('https://example.test', api_key: 'test', api_secret: 'test-secret')
    call = nil
    client.define_singleton_method(:rpc!) { |method, request, headers:| call = [method, request, headers] }
    client.remove_with_cutoff(room: 'abccanyoning-team', identity: 'mobile-test', cutoff: 12345)
    assert_equal :RemoveParticipant, call.first
    assert_equal 'abccanyoning-team', call[1].room
    assert_equal 'mobile-test', call[1].identity
    assert_equal 12345, call[1].revoke_token_ts
  end
end
