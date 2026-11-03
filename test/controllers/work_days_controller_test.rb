require "test_helper"

class WorkDaysControllerTest < ActionDispatch::IntegrationTest
  test "new programming loads before a date is entered" do
    user = User.create!(name: "New roll admin", email: "new-roll-admin@example.test",
      password: "password123", role: :admin)
    sign_in user
    CompensationRate.create!(code: "guide_regular", amount_cents: 5_000,
      effective_at: Time.utc(2020, 1, 1))

    get new_work_day_url

    assert_response :success
    assert_select "h1", "Nueva programación de guías"
    assert_select "input[name='work_day[date]']", count: 1
  end

  test "driver demand is saved by departure even with no guide slots" do
    user = User.create!(name: "Driver demand admin", email: "driver-demand-admin@example.test",
      password: "password123", role: :admin)
    sign_in user
    work_day = WorkDay.create!(date: Date.current + 3.days)

    locations = Departure::OPERATING_SECTIONS.keys.index_with do |_location|
      { guides: "0", drivers: "0", passengers: "0" }
    end
    locations["Balsa"][:drivers] = "2"
    locations["Balsa"][:passengers] = "14"

    post create_slots_work_day_url(work_day), params: { locations: locations }

    assert_redirected_to work_day_url(work_day)
    assert_equal 0, work_day.location_slots.count
    assert_equal 2, work_day.reload.drivers_requested_for("Balsa")
    assert_equal 0, work_day.drivers_requested_for("PM")

    get locations_work_day_url(work_day)
    assert_response :success
    assert_select "input[name='locations[Balsa][drivers]'][value='2']"
  end

  test "publishing sends TourFotos and WhatsApp notifications" do
    user = User.create!(
      name: "Roll Admin",
      email: "roll-admin@example.com",
      password: "password123",
      role: :admin
    )
    sign_in user
    work_day = WorkDay.create!(date: Date.current + 1.day, status: :generated)
    whatsapp_work_day = nil
    external_work_day = nil

    original_external_sender = ExternalRollSender.method(:send_work_day)
    original_whatsapp_sender = Whatsapp::RollNotificationSender.method(:send_work_day)
    ExternalRollSender.define_singleton_method(:send_work_day) { |day| external_work_day = day }
    Whatsapp::RollNotificationSender.define_singleton_method(:send_work_day) { |day| whatsapp_work_day = day }

    post publish_work_day_url(work_day)

    assert_redirected_to work_day_url(work_day)
    assert work_day.reload.published?
    assert_equal work_day, external_work_day
    assert_equal work_day, whatsapp_work_day
  ensure
    ExternalRollSender.define_singleton_method(:send_work_day, original_external_sender) if original_external_sender
    Whatsapp::RollNotificationSender.define_singleton_method(:send_work_day, original_whatsapp_sender) if original_whatsapp_sender
  end
end
