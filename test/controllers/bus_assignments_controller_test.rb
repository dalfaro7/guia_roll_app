require "test_helper"

class BusAssignmentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      name: "Test User",
      email: "busassignments@test.com",
      password: "password123",
      password_confirmation: "password123"
    )

    sign_in @user

    @bus = Bus.create!(
      company: "Test Company",
      capacity: 20,
      plate: "TEST-001",
      alias: "Bus Test",
      phone: "88888888"
    )

    @work_day = WorkDay.new(
      date: Date.current,
      status: :draft,
      guides_requested: 0
    )

    @work_day.save!(validate: false)

    @assignment = BusAssignment.create!(
      bus: @bus,
      work_day: @work_day,
      location: "Balsa",
      seats_assigned: 10
    )
  end

  test "should create bus assignment" do
    second_bus = Bus.create!(
      company: "Second Company",
      capacity: 25,
      plate: "TEST-002",
      alias: "Bus Test 2",
      phone: "87777777"
    )

    assert_difference("BusAssignment.count", 1) do
      post bus_assignments_path,
           params: {
             bus_assignment: {
               bus_id: second_bus.id,
               work_day_id: @work_day.id,
               location: "Sarapiqui",
               seats_assigned: 12
             }
           }
    end

    assert_response :redirect
  end

  test "should destroy bus assignment" do
    assert_difference("BusAssignment.count", -1) do
      delete bus_assignment_path(@assignment)
    end

    assert_redirected_to work_day_path(@work_day)
  end
end