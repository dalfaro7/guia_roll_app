require 'test_helper'
class ReportPushTest < ActionDispatch::IntegrationTest
  def stub_gateway(name,value)
    original=KayaktalkiePushGateway.method(name)
    KayaktalkiePushGateway.define_singleton_method(name) { |*args| value.respond_to?(:call) ? value.call(*args) : value }
    yield
  ensure
    KayaktalkiePushGateway.define_singleton_method(name,original)
  end
  setup do
    @team=KayaktalkieTeam.create!(name:'Push team')
    @other=KayaktalkieTeam.create!(name:'Push other')
    @accounts=4.times.map { |i| KayaktalkieAccount.create!(name:"Push #{i}",phone:"8888555#{i}",password:'Push-test-1234567',role:i==3 ? 'admin' : 'staff') }
    @accounts[0].kayaktalkie_teams << @team;@accounts[1].kayaktalkie_teams << @team;@accounts[2].kayaktalkie_teams << @other
    @tokens=@accounts.map { |account|KayaktalkieSession.issue!(account) }
    @sessions=@accounts.map { |account|account.kayaktalkie_sessions.last }
    @sessions.each_with_index { |session,i|session.update!(expo_push_token:"ExpoPushToken[test_device_token_#{i}]") }
    @report=KayaktalkieFieldReport.create!(kayaktalkie_account:@accounts[0],kayaktalkie_team:@team,client_id:'push-report-test-123456',kind:'road_closed',latitude:10,longitude:-84,accuracy:10,observed_at:Time.current)
  end
  def auth(i) = {'Authorization'=>"Bearer #{@tokens[i]}"}
  test 'notification detail enforces current team and expiration' do
    get "/api/field_reports/#{@report.id}",headers:auth(1);assert_response :success
    get "/api/field_reports/#{@report.id}",headers:auth(2);assert_response :not_found
    @accounts[1].kayaktalkie_team_memberships.delete_all
    get "/api/field_reports/#{@report.id}",headers:auth(1);assert_response :not_found
    @report.update_columns(created_at:61.minutes.ago)
    get "/api/field_reports/#{@report.id}",headers:auth(3);assert_response :not_found
  end
  test 'push sends only to current team and admin once without coordinates or text' do
    sent=[]
    fake=->(session,report){sent<<session.id;{'status'=>'ok','id'=>"ticket-#{session.id}"}}
    stub_gateway(:enabled?,true) do
      stub_gateway(:send_report,fake) do
        KayaktalkieNotifyFieldReportJob.perform_now(@report.id)
        KayaktalkieNotifyFieldReportJob.perform_now(@report.id)
      end
    end
    assert_equal [@sessions[1].id,@sessions[3].id].sort,sent.sort
    payload=nil
    stub_gateway(:post,->(_endpoint,data){payload=data;{'status'=>'ok','id'=>'x'}}) {KayaktalkiePushGateway.send_report(@sessions[1],@report)}
    assert_not payload.to_json.include?('latitude')
    assert_not payload.to_json.include?(@team.name)
    assert_equal @accounts[1].id,payload[:data][:accountId]
    assert_operator payload[:ttl],:<=,3600
  end
  test 'revoked expired and resolved recipients are not sent alerts' do
    @accounts[1].update!(active:false)
    @sessions[3].update!(expires_at:1.second.ago)
    stub_gateway(:enabled?,true) do
      stub_gateway(:send_report,->(*){flunk 'Unauthorized push'}) {KayaktalkieNotifyFieldReportJob.perform_now(@report.id)}
    end
    assert_empty KayaktalkieReportDelivery.where(kayaktalkie_field_report:@report)
  end
  test 'device token moves to current session and browser cannot register it' do
    token=@sessions[1].expo_push_token
    post '/api/push/token',params:{token:token},headers:auth(2),as: :json;assert_response :success
    assert_nil @sessions[1].reload.expo_push_token
    assert_equal token,@sessions[2].reload.expo_push_token
    post '/api/push/token',params:{token:'invalid'},headers:auth(2),as: :json;assert_response :unprocessable_entity
    delete '/api/push/token',headers:auth(2);assert_response :success
    assert_nil @sessions[2].reload.expo_push_token
  end
end
