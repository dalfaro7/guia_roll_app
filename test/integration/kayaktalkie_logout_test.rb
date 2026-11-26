require 'test_helper'

class KayaktalkieLogoutTest < ActionDispatch::IntegrationTest
  setup do
    @previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    @account = KayaktalkieAccount.create!(name: 'Logout test', phone: '+50689994411',
      password: 'Logout-test-123456', role: 'staff', active: true)
    get kayaktalkie_login_path
    post kayaktalkie_login_path, params: {phone: @account.phone,
      password: 'Logout-test-123456', authenticity_token: token}
    assert_response :redirect
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @previous
  end

  test 'stale logout requires fresh confirmation and then revokes session' do
    assert_no_difference('KayaktalkieSession.count') do
      post kayaktalkie_logout_path, params: {authenticity_token: 'stale'}
    end
    assert_redirected_to kayaktalkie_logout_path
    follow_redirect!
    assert_response :success
    assert_equal 'no-store', response.headers['Cache-Control']
    assert_difference('KayaktalkieSession.count', -1) do
      post kayaktalkie_logout_path, params: {authenticity_token: token}
    end
    assert_redirected_to kayaktalkie_login_path
    get kayaktalkie_path
    assert_redirected_to kayaktalkie_login_path
  end

  test 'opening logout URL does not revoke a session' do
    assert_no_difference('KayaktalkieSession.count') { get kayaktalkie_logout_path }
    assert_response :success
  end

  test 'invalid login token is still rejected' do
    post kayaktalkie_login_path, params: {phone: @account.phone,
      password: 'Logout-test-123456', authenticity_token: 'stale'}
    assert_response :unprocessable_entity
  end

  private
  def token
    Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')['content']
  end
end
