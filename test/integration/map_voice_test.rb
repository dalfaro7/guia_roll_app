require 'test_helper'
class MapVoiceTest < ActionDispatch::IntegrationTest
  setup do
    @admin=User.create!(name:'Mapa admin',email:'map-voice@example.test',password:'Map-voice-test-123456',role: :admin)
    @guide=Guide.create!(name:'Guía radio',active:true,priority:1)
    @account=MobileAccount.create!(guide:@guide,phone:'88887771',password:'Map-voice-test-123456')
  end
  test 'map voice mapping only exposes current session ids to administrator' do
    MobileSession.issue!(@account);active=@account.mobile_sessions.last
    MobileSession.issue!(@account);@account.mobile_sessions.last.update!(expires_at:1.second.ago)
    sign_in @admin;get '/api/users';assert_response :success
    row=response.parsed_body.find { |user| user['id']==@guide.id }
    assert_equal ["mobile-#{active.id}"],row['voice_identities']
    assert_not row.to_s.include?(active.token_digest)
  end
  test 'only administrator can read active PTT turn and expired turns are cleared' do
    get '/api/map/voice';assert_response :unauthorized
    headers={'Authorization'=>"Bearer #{MobileSession.issue!(@account)}"}
    get '/api/map/voice',headers:headers;assert_response :unauthorized
    @admin.update!(role: :operador);sign_in @admin
    get '/api/map/voice';assert_response :forbidden
    @admin.update!(role: :admin);sign_in @admin
    floor=VoiceFloor.general
    floor.update!(holder_identity:'mobile-123',holder_name:'Guía radio',expires_at:20.seconds.from_now,lease_id:'test')
    get '/api/map/voice';assert_response :success
    assert_equal 'mobile-123',response.parsed_body['speakers'].first['identity']
    assert_equal 'no-store',response.headers['Cache-Control']
    floor.update!(expires_at:1.second.ago)
    get '/api/map/voice';assert_response :success
    assert_empty response.parsed_body['speakers']
  end
end
