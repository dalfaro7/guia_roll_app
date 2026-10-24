require 'test_helper'
class MapAreaTest < ActionDispatch::IntegrationTest
  setup do
    @operator = KayaktalkieAccount.create!(name: 'Area operator', phone: '88887760', password: 'Map-area-test-123456', role: 'operator')
    @other = KayaktalkieAccount.create!(name: 'Other operator', phone: '88887761', password: 'Map-area-test-123456', role: 'operator')
    @headers = { 'Authorization' => "Bearer #{KayaktalkieSession.issue!(@operator)}" }
    @area = {lat: 10.4, lng: -84.6, zoom: 16}
  end
  test 'area belongs to authenticated account and is returned to another session' do
    post '/api/map/area', params: {area: @area, account_id: @other.id}, headers: @headers, as: :json
    assert_response :success
    assert_nil @other.reload.map_area
    other_session = {'Authorization' => "Bearer #{KayaktalkieSession.issue!(@operator)}"}
    get '/api/me', headers: other_session
    assert_equal @area.stringify_keys, response.parsed_body['map_area']
    post '/api/map/area', params: {area: @area.merge(zoom: 12), import: true}, headers: @headers, as: :json
    assert_equal 16, @operator.reload.map_area['zoom']
  end
  test 'staff anonymous and invalid coordinates cannot save areas' do
    post '/api/map/area', params: {area: @area}, as: :json
    assert_response :unauthorized
    @other.update!(role: 'staff')
    post '/api/map/area', params: {area: @area}, headers: {'Authorization' => "Bearer #{KayaktalkieSession.issue!(@other)}"}, as: :json
    assert_response :forbidden
    [{lat: 100}, {lng: 181}, {zoom: 20}, {zoom: '16'}, {lat: nil}].each do |invalid|
      post '/api/map/area', params: {area: @area.merge(invalid)}, headers: @headers, as: :json
      assert_response :unprocessable_entity
    end
    assert_nil @operator.reload.map_area
  end
  test 'browser writes require csrf token' do
    post '/kayaktalkie/login', params: {phone: @operator.phone, password: 'Map-area-test-123456'}
    post '/api/map/area', params: {area: @area}, as: :json
    assert_response :forbidden
  end
end
