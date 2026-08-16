require "test_helper"

class BusesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      name: "Test User",
      email: "bus_test@example.com",
      password: "password123",
      password_confirmation: "password123"
    )

    sign_in @user

    @bus = Bus.create!(
      company: "Test Company",
      capacity: 20,
      plate: "TEST-001",
      alias: "Test Bus",
      phone: "8888-8888"
    )
  end

  test "should get index" do
    get buses_url
    assert_response :success
  end

  test "should get show" do
    get bus_url(@bus)
    assert_response :success
  end

  test "should get new" do
    get new_bus_url
    assert_response :success
  end

  test "should get edit" do
    get edit_bus_url(@bus)
    assert_response :success
  end
end