require 'test_helper'
class OfficeAccountsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  setup do
    @a=VoiceChannel.find_by!(room_key: VoiceFloor::ROOM)
    @b=VoiceChannel.find_by!(room_key: 'abccanyoning-team')
    @staff=make_account('staff', '89991001', [@a], true)
    @other=make_account('staff', '89991002', [@b], true)
    @operator=make_account('operator', '89991003', [@a])
    @admin=make_account('admin', '89991004', [])
  end
  def make_account(role, phone, channels, gps=false)
    account=KayaktalkieAccount.new
    KayaktalkieAccess.assign!(account, attributes:{name: "#{role} #{phone}",role:role,phone:phone,password:'Independent-test-123456',location_enabled:gps},team_ids:channels.map(&:kayaktalkie_team_id),channel_ids:channels.map(&:id))
    account
  end
  def login(account)
    post '/kayaktalkie/login',params:{phone:account.phone,password:'Independent-test-123456'}
    assert_response :redirect
  end
  test 'operators see only assigned team positions and assigned channel speakers' do
    [@staff,@other].each { |a| KayaktalkieTrackingIngest.call(a,{'latitude'=>10.4,'longitude'=>-84.6,'accuracy'=>10,'capturedAt'=>Time.current.to_f*1000}) }
    [@a,@b].each { |c| VoiceFloor.for_channel(c).update!(holder_identity:"channel-#{c.id}",expires_at:20.seconds.from_now) }
    login(@operator)
    get '/tracking';assert_response :success
    assert_select '#voiceChannel option',count:2
    assert_select 'a[href="/tracking/accounts"]',count:0
    assert_select 'a[href="/dashboard"]',count:0
    get '/api/users';assert_equal [@staff.id],response.parsed_body.map { |x| x['id'] }
    get '/api/map/voice';assert_equal ["channel-#{@a.id}"],response.parsed_body['speakers'].map { |s| s['identity'] }
    get '/api/voice/channels';assert_equal [@a.id],response.parsed_body['channels'].map { |c| c['id'] }
    get '/api/reports/speed';assert_response :forbidden
    get '/tracking/accounts';assert_response :forbidden
    get '/dashboard';assert_redirected_to new_user_session_path
  end
  test 'map removes unassigned accounts but preserves history and other team membership' do
    KayaktalkieTrackingIngest.call(@staff, {'latitude'=>10.4,'longitude'=>-84.6,'accuracy'=>10,'capturedAt'=>Time.current.to_f*1000})
    login(@admin)
    get '/api/users'
    assert_includes response.parsed_body.map { |u| u['id'] }, @staff.id
    KayaktalkieAccess.assign!(@staff, attributes:{}, team_ids:[], channel_ids:[])
    get '/api/users'
    assert_not_includes response.parsed_body.map { |u| u['id'] }, @staff.id
    assert_equal 'no-store', response.headers['Cache-Control']
    assert @staff.reload.active?
    assert @staff.kayaktalkie_position.present?
    KayaktalkieAccess.assign!(@staff, attributes:{}, team_ids:[@b.kayaktalkie_team_id], channel_ids:[])
    get '/api/users'
    assert_includes response.parsed_body.map { |u| u['id'] }, @staff.id
    login(@operator)
    get '/api/users'
    assert_not_includes response.parsed_body.map { |u| u['id'] }, @staff.id
  end
  test 'forged channel ids deny join claim release and status across teams' do
    headers={'Authorization'=>"Bearer #{KayaktalkieSession.issue!(@operator)}"}
    %w[join claim release].each do |action|
      post "/api/voice/#{action}",params:{channel_id:@b.id,lease:'forged'},headers:headers,as: :json
      assert_response :forbidden
    end
    get '/api/voice/status',params:{channel_id:@b.id},headers:headers;assert_response :forbidden
    @operator.voice_memberships.destroy_all
    get '/api/voice/channels',headers:headers;assert_empty response.parsed_body['channels']
    get '/api/users',headers:headers;assert_response :success # Map team permission is distinct from channel permission.
  end
  test 'staff has voice only web access and GPS remains an explicit capability' do
    login(@staff);follow_redirect!;assert_response :success
    get '/tracking';assert_response :forbidden
    get '/api/users';assert_response :forbidden
    @staff.update!(location_enabled:false)
    headers={'Authorization'=>"Bearer #{KayaktalkieSession.issue!(@staff)}"}
    post '/api/location',params:{latitude:10.4,longitude:-84.6,accuracy:1,capturedAt:Time.current.to_f*1000},headers:headers,as: :json
    assert_response :forbidden
    assert_not @staff.has_attribute?(:guide_id)
    assert_not @staff.has_attribute?(:account_type)
  end
  test 'Guia Roll administrator gets no implicit Kayak access' do
    u=User.create!(name:'Separate admin',email:'separate-admin@example.test',password:'Independent-test-123456',role: :admin)
    sign_in u
    get '/tracking';assert_redirected_to kayaktalkie_login_path
    get '/api/users';assert_response :unauthorized
    post '/api/voice/join',as: :json;assert_response :unauthorized
  end
  test 'admin can create independent teams and accounts but operators cannot escalate' do
    login(@admin)
    assert_difference 'KayaktalkieTeam.count',1 do
      post '/tracking/teams',params:{kayaktalkie_team:{name:'Independent rescue'}}
    end
    assert_difference 'KayaktalkieAccount.count',1 do
      post '/tracking/accounts',params:{kayaktalkie_account:{name:'New operator',phone:'89991005',password:'Independent-test-123456',role:'operator',location_enabled:false},team_ids:[@b.kayaktalkie_team_id],voice_channel_ids:[@b.id]}
    end
    assert_redirected_to tracking_accounts_path
    login(@operator)
    patch "/tracking/accounts/#{@operator.id}/channels",params:{kayaktalkie_account:{role:'admin'},team_ids:[@b.kayaktalkie_team_id],voice_channel_ids:[@b.id]}
    assert_response :forbidden
    assert_equal 'operator',@operator.reload.role
  end
  test 'invalid cross-team assignment is atomic and removal revokes active voice access' do
    assert_raises(ArgumentError) { KayaktalkieAccess.assign!(@operator,attributes:{role:'admin'},team_ids:[@a.kayaktalkie_team_id],channel_ids:[@b.id]) }
    assert_equal 'operator',@operator.reload.role
    assert_enqueued_with(job:VoiceRevokeAccessJob,args:[@operator.id,@a.id]) do
      KayaktalkieAccess.assign!(@operator,attributes:{},team_ids:[],channel_ids:[])
    end
    assert_empty @operator.reload.allowed_channels
    login(@operator);get '/api/users';assert_empty response.parsed_body
  end
  test 'moving a staff member does not expose the previous teams last coordinates' do
    KayaktalkieTrackingIngest.call(@staff,{'latitude'=>10.4,'longitude'=>-84.6,'accuracy'=>10,'capturedAt'=>Time.current.to_f*1000})
    KayaktalkieAccess.assign!(@staff,attributes:{},team_ids:[@b.kayaktalkie_team_id],channel_ids:[@b.id])
    second=make_account('operator','89991006',[@b]);login(second)
    get '/api/users';row=response.parsed_body.find { |x| x['id']==@staff.id };assert_nil row['latitude']
  end
  test 'disabling account invalidates sessions and enqueues removal for all assigned channels' do
    token=KayaktalkieSession.issue!(@staff)
    identities = @staff.kayaktalkie_sessions.map { |session| "mobile-#{session.id}" }
    assert_enqueued_with(job:VoiceRevokeAccessJob,args:[@staff.id,@a.id,identities]) do
      KayaktalkieAccess.assign!(@staff,attributes:{active:false},team_ids:[@a.kayaktalkie_team_id],channel_ids:[@a.id])
    end
    assert_nil KayaktalkieSession.authenticate(token)
  end
  test 'disabled accounts lose every session and cannot login until reactivated' do
    first = KayaktalkieSession.issue!(@staff)
    second = KayaktalkieSession.issue!(@staff)
    login(@staff)
    KayaktalkieAccess.assign!(@staff, attributes:{active:false}, team_ids:[@a.kayaktalkie_team_id], channel_ids:[@a.id])
    assert_empty @staff.reload.kayaktalkie_sessions
    [first, second].each do |token|
      get '/api/account', headers:{'Authorization'=>"Bearer #{token}"}
      assert_response :unauthorized
    end
    get '/kayaktalkie'
    assert_redirected_to kayaktalkie_login_path
    post '/api/login', params:{phone:@staff.phone,password:'Independent-test-123456'}, as: :json
    assert_response :unauthorized
    post '/kayaktalkie/login', params:{phone:@staff.phone,password:'Independent-test-123456'}
    assert_response :unprocessable_entity
    KayaktalkieAccess.assign!(@staff, attributes:{active:true}, team_ids:[@a.kayaktalkie_team_id], channel_ids:[@a.id])
    assert_nil KayaktalkieSession.authenticate(first)
    assert_nil KayaktalkieSession.authenticate(second)
    post '/api/login', params:{phone:@staff.phone,password:'Independent-test-123456'}, as: :json
    assert_response :success
    assert KayaktalkieSession.authenticate(response.parsed_body['token'])
  end
  test 'browser voice and location mutations require CSRF' do
    login(@staff)
    [ActionController::Base,VoiceController,TrackingApiController].each { |c| c.allow_forgery_protection=true }
    post '/api/voice/claim',params:{channel_id:@a.id},as: :json;assert_response :forbidden
    post '/api/location',params:{},as: :json;assert_response :forbidden
  ensure
    [ActionController::Base,VoiceController,TrackingApiController].each { |c| c.allow_forgery_protection=false }
  end
end
