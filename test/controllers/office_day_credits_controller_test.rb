require "test_helper"

class OfficeDayCreditsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get office_day_credits_index_url
    assert_response :success
  end
end
