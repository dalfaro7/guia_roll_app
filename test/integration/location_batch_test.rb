require 'test_helper'
class LocationBatchTest < ActionDispatch::IntegrationTest
  setup do
    @account=KayaktalkieAccount.create!(name:'Batch user',phone:'88883321',role:'staff',password:'Batch-test-123456',location_enabled:true)
    @headers={'Authorization'=>"Bearer #{KayaktalkieSession.issue!(@account)}"}
    @start=Time.current-120.seconds
  end
  def point(seconds)
    {latitude:10.0,longitude:-84.0+seconds*0.00001,accuracy:5,capturedAt:(@start.to_f+seconds)*1000,speedMps:nil}
  end
  test 'batch sorts captures retains intermediate points and retries safely' do
    post '/api/location/batch',params:{samples:[point(20),point(0),point(10)]},headers:@headers,as: :json
    assert_response :success
    assert_equal 3,response.parsed_body['accepted']
    position=KayaktalkiePosition.find_by!(kayaktalkie_account:@account)
    assert_equal 3,position.speed_samples.size
    post '/api/location/batch',params:{samples:[point(0),point(10),point(20)]},headers:@headers,as: :json
    assert_response :success
    assert_equal 0,response.parsed_body['accepted']
    post '/api/location/batch',params:{samples:[point(30),point(40),point(50),point(60)]},headers:@headers,as: :json
    assert_response :success
    assert_equal 60,position.reload.speed_estimate['window_seconds']
  end
  test 'invalid sample rolls back entire batch and size is bounded' do
    post '/api/location/batch',params:{samples:[point(0),point(10).merge(latitude:200)]},headers:@headers,as: :json
    assert_response :bad_request
    assert_nil KayaktalkiePosition.find_by(kayaktalkie_account:@account)
    post '/api/location/batch',params:{samples:Array.new(61){point(0)}},headers:@headers,as: :json
    assert_response :bad_request
    post '/api/location/batch',params:{samples:[point(0)]},as: :json
    assert_response :unauthorized
  end
end
