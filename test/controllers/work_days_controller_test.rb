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

  test "published operation shows the PM vehicle and driver beside its assigned river team" do
    user = User.create!(name: "Operation admin", email: "operation-admin@example.test",
      password: "password123", role: :admin)
    sign_in user
    day = WorkDay.create!(date: Date.current + 2.days, status: :published,
      guides_requested: 0)
    day.location_slots.create!(location: "Sara-3&4", passengers: 14)
    company = TransportCompany.create!(name: "Transportes PM")
    driver = Driver.create!(name: "Diego", phone: "555-1010",
      transport_company: company)
    bus = Bus.create!(transport_company: company, alias: "Bus PM",
      plate: "PM-101", capacity: 20)
    BusAssignment.create!(bus: bus, driver: driver, work_day: day,
      location: "PM", seats_assigned: 4)

    get work_day_path(day)
    assert_response :success
    assert_select "h2#day-assigned", text: "Equipo y transporte por salida"
    assert_select "tr[data-location-section='PM']", count: 1
    assert_select "tr[data-transport-location='PM']", text: /Bus PM.*Chofer asignado: Diego/
    assert_select "tr[data-guide-warning='Sara-3&4']", text: /14 pasajeros y ningún guía de río/
    assert_select "h2#day-transport", count: 0
  end

  test "published distribution keeps the old roll table and groups guides and drivers by outing" do
    user = User.create!(name: "Distribution admin", email: "distribution-admin@example.test",
      password: "password123", role: :admin)
    sign_in user
    guides = ["Balsa guide", "Sara guide", "Task guide", "Waiting guide", "Free guide", "Penalized guide"].map do |name|
      Guide.create!(name: name, priority: 3, active: true)
    end
    day = WorkDay.create!(date: Date.current + 2.days, status: :published)
    statuses = %w[worked worked assigned_task standby day_off penalized]
    guides.zip(statuses).each do |guide, status|
      attrs = { status: GuideDay.statuses.fetch(status) }
      if status == "worked"
        attrs.merge!(location: guide.name == "Sara guide" ? "Sara-3" : "Balsa",
          role_primary: "River Guide", role_secondary: "Head Guide")
      end
      attrs[:status_note] = "Host" if status == "assigned_task"
      attrs[:status_note] = "Falta" if status == "penalized"
      day.guide_days.find_by!(guide: guide).update_columns(attrs)
    end
    company = TransportCompany.create!(name: "Distribution transport")
    driver = Driver.create!(name: "Distribution driver", transport_company: company)
    bus = Bus.create!(transport_company: company, alias: "Bus Balsa",
      plate: "DB-101", capacity: 20)
    BusAssignment.create!(bus: bus, driver: driver, work_day: day,
      location: "Balsa", seats_assigned: 6)

    get work_day_path(day)
    assert_select "a[href='#{distribution_work_day_path(day)}']", text: "Distribución de guías y choferes"

    get distribution_work_day_path(day)
    assert_response :success
    assert_select "h1", "Distribución de guías y choferes"
    assert_equal ["Salida", "#", "Guía o chofer", "Principal", "Secundario", "Estado"],
      css_select("#distribution-table thead th").map(&:text)
    assert_equal ["Balsa", "Sara-3&4"],
      css_select("tr[data-location-section]").map { |row| row["data-location-section"] }
    assert_select "tr.distribution-empty", count: 0
    assert_select "tr[data-location-section='Balsa'] th.distribution-section-cell[scope='rowgroup'][rowspan='2']", text: "Balsa"
    assert_select "tr[data-location-section='Sara-3&4'] th.distribution-section-cell[scope='rowgroup']", text: "Sara 3/4"
    assert_select "tr[data-section='Sara-3&4'][data-person-kind='guide']", text: /Sara guide.*Sara-3.*Guía de río/
    assert_select "tr[data-section='Balsa'] td", text: "Balsa", count: 0
    assert_equal ["Tarea asignada", "En espera", "Libres", "Penalizados"],
      css_select("tr[data-status-group]").map { |row| row["data-status-group"] }
    assert_select "tr[data-section='Balsa'][data-person-kind='guide']", text: /Balsa guide.*Guía de río.*HG.*Trabaja/
    assert_select "tr[data-section='Balsa'][data-person-kind='driver']", text: /Distribution driver.*Chofer.*Bus Balsa/
    assert_select "tr[data-status-section='Tarea asignada']", text: /Task guide.*Host/
    assert_select "tr[data-status-section='En espera']", text: /Waiting guide/
    assert_select "tr[data-status-section='Libres']", text: /Free guide/
    assert_select "tr[data-status-section='Penalizados']", text: /Penalized guide.*Falta/
  end
end
