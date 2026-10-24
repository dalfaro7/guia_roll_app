require 'test_helper'
class MapVoiceTest < ActionDispatch::IntegrationTest
  setup do
    @admin=KayaktalkieAccount.create!(name:'Mapa admin',phone:'88887770',password:'Map-voice-test-123456',role:'admin')
    @account=KayaktalkieAccount.create!(name:'Staff radio',phone:'88887771',password:'Map-voice-test-123456',location_enabled:true)
  end
  test 'map voice mapping exposes only current session ids without digests' do
    @account.kayaktalkie_teams << KayaktalkieTeam.first!
    KayaktalkieSession.issue!(@account);active=@account.kayaktalkie_sessions.last
    KayaktalkieSession.issue!(@account);@account.kayaktalkie_sessions.last.update!(expires_at:1.second.ago)
    post '/kayaktalkie/login', params:{phone:@admin.phone,password:'Map-voice-test-123456'}
    get '/api/users';assert_response :success
    row=response.parsed_body.find { |user| user['id']==@account.id }
    assert_equal ["mobile-#{active.id}"],row['voice_identities']
    assert_not row.to_s.include?(active.token_digest)
  end
  test 'staff cannot read map turns and expired turns disappear' do
    get '/api/map/voice';assert_response :unauthorized
    headers={'Authorization'=>"Bearer #{KayaktalkieSession.issue!(@account)}"}
    get '/api/map/voice',headers:headers;assert_response :forbidden
    post '/kayaktalkie/login', params:{phone:@admin.phone,password:'Map-voice-test-123456'}
    floor=VoiceFloor.general
    floor.update!(holder_identity:'mobile-123',holder_name:'Staff radio',expires_at:20.seconds.from_now,lease_id:'test')
    get '/api/map/voice';assert_response :success
    assert_equal 'mobile-123',response.parsed_body['speakers'].first['identity']
    assert_equal 'no-store',response.headers['Cache-Control']
    floor.update!(expires_at:1.second.ago)
    get '/api/map/voice';assert_empty response.parsed_body['speakers']
  end
end
