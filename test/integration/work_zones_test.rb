require 'test_helper'
class WorkZonesTest < ActionDispatch::IntegrationTest
  setup do
    @team=KayaktalkieTeam.create!(name:'Zone team')
    @other=KayaktalkieTeam.create!(name:'Private zone team')
    @operator=KayaktalkieAccount.create!(name:'Zone operator',phone:'88885510',role:'operator',password:'Zone-test-123456')
    @staff=KayaktalkieAccount.create!(name:'Zone staff',phone:'88885511',role:'staff',password:'Zone-test-123456')
    @operator.kayaktalkie_teams << @team
    @peer=KayaktalkieAccount.create!(name:'Peer',phone:'88885512',role:'operator',password:'Zone-test-123456')
    @peer.kayaktalkie_teams << @team
    @peer.kayaktalkie_teams << @other
    @headers={'Authorization'=>"Bearer #{KayaktalkieSession.issue!(@operator)}"}
    @params={team_id:@team.id,name:'Rancho',latitude:10.4,longitude:-84.5,radius_m:500}
  end
  test 'operator zones persist and are isolated by team' do
    post '/api/map/zones',params:@params,headers:@headers,as: :json
    assert_response :created
    id=response.parsed_body['id']
    patch "/api/map/zones/#{id}",params:{radius_m:600},headers:@headers,as: :json
    assert_response :success
    assert_equal 600,KayaktalkieWorkZone.find(id).radius_m
    private_zone=KayaktalkieWorkZone.create!(kayaktalkie_team:@other,operator:@peer,name:'Private',latitude:10,longitude:-84,radius_m:500)
    peer_zone=KayaktalkieWorkZone.create!(kayaktalkie_team:@team,operator:@peer,name:'Peer area',latitude:10,longitude:-84,radius_m:500)
    patch "/api/map/zones/#{peer_zone.id}",params:{name:'Not allowed'},headers:@headers,as: :json
    assert_response :not_found
    get '/api/map/zones',headers:@headers
    assert_equal [id],response.parsed_body['zones'].map{|z|z['id']}
    delete "/api/map/zones/#{private_zone.id}",headers:@headers
    assert_response :not_found
    post '/api/map/zones',params:@params.merge(team_id:@other.id),headers:@headers,as: :json
    assert_response :not_found
    delete "/api/map/zones/#{id}",headers:@headers
    assert_response :no_content
  end
  test 'invalid geometry and staff writes are rejected' do
    post '/api/map/zones',params:@params.merge(radius_m:0),headers:@headers,as: :json
    assert_response :unprocessable_entity
    post '/api/map/zones',params:@params,headers:{'Authorization'=>"Bearer #{KayaktalkieSession.issue!(@staff)}"},as: :json
    assert_response :forbidden
  end
end
