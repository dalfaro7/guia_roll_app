require 'test_helper'
class FieldReportsTest < ActionDispatch::IntegrationTest
  setup do
    @team=KayaktalkieTeam.create!(name:'Report team')
    @other_team=KayaktalkieTeam.create!(name:'Other report team')
    @staff=KayaktalkieAccount.create!(name:'Reporter',phone:'88886660',role:'staff',password:'Report-test-123456')
    @operator=KayaktalkieAccount.create!(name:'Report operator',phone:'88886661',role:'operator',password:'Report-test-123456')
    @outsider=KayaktalkieAccount.create!(name:'Other operator',phone:'88886662',role:'operator',password:'Report-test-123456')
    @admin=KayaktalkieAccount.create!(name:'Report admin',phone:'88886663',role:'admin',password:'Report-test-123456')
    [@staff,@operator].each { |a| a.kayaktalkie_teams << @team }
    @outsider.kayaktalkie_teams << @other_team
    @params={team_id:@team.id,client_id:'report-test-123456789',kind:'wildlife',animal:'sloths',latitude:10.2,longitude:-84.2,accuracy:12,observed_at:Time.current.iso8601}
  end
  def auth(account) = {'Authorization'=>"Bearer #{KayaktalkieSession.issue!(account)}"}
  def create_report(extra={})
    post '/api/field_reports',params:@params.merge(extra),headers:auth(@staff),as: :json
    assert_response :created
    response.parsed_body['id']
  end
  test 'team scoped reports persist with correct timestamp and idempotency' do
    id=create_report
    post '/api/field_reports',params:@params,headers:auth(@staff),as: :json
    assert_response :success;assert_equal id,response.parsed_body['id']
    get '/api/field_reports',headers:auth(@operator);assert_equal [id],response.parsed_body['items'].map { |r|r['id'] }
    get '/api/field_reports',headers:auth(@outsider);assert_empty response.parsed_body['items']
    post "/api/field_reports/#{id}/resolve",headers:auth(@outsider);assert_response :not_found
    post "/api/field_reports/#{id}/resolve",headers:auth(@staff);assert_response :forbidden
    post "/api/field_reports/#{id}/resolve",headers:auth(@operator);assert_response :success
    get '/api/field_reports',headers:auth(@staff);assert_empty response.parsed_body['items']
    assert_equal @operator.id,KayaktalkieFieldReport.find(id).resolved_by_id
  end
  test 'invalid categories animals coordinates and team assignment are rejected' do
    [{kind:'invalid'},{animal:'other',description:''},{latitude:91},{observed_at:2.days.ago.iso8601}].each do |extra|
      post '/api/field_reports',params:@params.merge(extra),headers:auth(@staff),as: :json
      assert_response :unprocessable_entity
    end
    post '/api/field_reports',params:@params.merge(team_id:@other_team.id),headers:auth(@staff),as: :json
    assert_response :forbidden
    post '/api/field_reports',params:@params,as: :json;assert_response :unauthorized
  end
  test 'browser writes reject missing csrf' do
    post '/kayaktalkie/login',params:{phone:@operator.phone,password:'Report-test-123456'}
    post '/api/field_reports',params:@params,as: :json;assert_response :forbidden
  end
  test 'new road categories are accepted and photos are rejected' do
    %w[road_closed police_checkpoint].each_with_index do |kind,i|
      id=create_report(kind:kind,client_id:"new-category-report-#{i}")
      assert_equal kind,KayaktalkieFieldReport.find(id).kind
    end
    assert_no_difference 'KayaktalkieFieldReport.count' do
      post '/api/field_reports',params:@params.merge(photo:'unsupported'),headers:auth(@staff),as: :json
      assert_response :unprocessable_entity
    end
  end
  test 'expired reports are hidden and deleted including resolved reports' do
    id=create_report
    report=KayaktalkieFieldReport.find(id)
    report.update_columns(created_at:59.minutes.ago)
    KayaktalkieExpireFieldReportsJob.perform_now
    assert KayaktalkieFieldReport.exists?(id)
    report.update_columns(created_at:1.hour.ago)
    get '/api/field_reports',headers:auth(@staff);assert_empty response.parsed_body['items']
    post '/api/field_reports',params:@params,headers:auth(@staff),as: :json;assert_response :gone
    report.update_columns(resolved_at:Time.current)
    KayaktalkieExpireFieldReportsJob.perform_now
    assert_not KayaktalkieFieldReport.exists?(id)
    KayaktalkieExpireFieldReportsJob.perform_now
  end
end
