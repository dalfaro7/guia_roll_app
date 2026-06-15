require "test_helper"

class OfficeEmployeeDaysControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get office_employee_days_index_url
    assert_response :success
  end
end
