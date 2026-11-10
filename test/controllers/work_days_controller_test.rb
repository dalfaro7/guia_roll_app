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

  test "location settings save without requesting drivers" do
    user = User.create!(name: "Location admin", email: "location-admin@example.test",
      password: "password123", role: :admin)
    sign_in user
    work_day = WorkDay.create!(date: Date.current + 3.days,
      drivers_requested_by_location: { "Balsa" => 2 })

    locations = Departure::OPERATING_SECTIONS.keys.index_with do |_location|
      { guides: "0", passengers: "0" }
    end
    locations["Balsa"][:guides] = "1"
    locations["Balsa"][:passengers] = "14"

    post create_slots_work_day_url(work_day), params: { locations: locations }

    assert_redirected_to work_day_url(work_day)
    assert_equal 1, work_day.location_slots.count
    assert_equal 14, work_day.location_slots.find_by!(location: "Balsa").passengers
    assert_equal 2, work_day.reload.drivers_requested_for("Balsa")

    get locations_work_day_url(work_day)
    assert_response :success
    assert_select "input[name$='[drivers]']", count: 0
    assert_select "th", text: "Choferes requeridos", count: 0
  end

  test "Sara PM and Private default requirements keep one specialized first slot" do
    user = User.create!(name: "Slot defaults admin", email: "slot-defaults-admin@example.test",
      password: "password123", role: :admin)
    sign_in user
    skills = %w[ClassIII ClassIV Busguide Computer Elite].index_with do |name|
      Skill.find_or_create_by!(name: name)
    end
    work_day = WorkDay.create!(date: Date.current + 3.days)
    locations = Departure::OPERATING_SECTIONS.keys.index_with do |_location|
      { guides: "0", passengers: "0" }
    end
    locations["Sara-3&4"][:guides] = "2"
    locations["PM"][:guides] = "2"
    locations["Balsa"][:guides] = "1"
    locations["Privado"][:guides] = "2"

    post create_slots_work_day_url(work_day), params: { locations: locations }

    assert_redirected_to work_day_url(work_day)
    sara_slots = work_day.location_slots.where(location: "Sara-3&4").order(:id).to_a
    pm_slots = work_day.location_slots.where(location: "PM").order(:id).to_a
    private_slots = work_day.location_slots.where(location: "Privado").order(:id).to_a
    assert_equal %w[Busguide ClassIV Computer], sara_slots.first.skills.pluck(:name).sort
    assert_equal %w[ClassIV], sara_slots.second.skills.pluck(:name).sort
    assert_equal %w[Busguide ClassIV Computer], pm_slots.first.skills.pluck(:name).sort
    assert_equal %w[ClassIV], pm_slots.second.skills.pluck(:name).sort
    assert_equal %w[ClassIII], work_day.location_slots.find_by!(location: "Balsa").skills.pluck(:name)
    assert_equal %w[ClassIII Elite], private_slots.first.skills.pluck(:name).sort
    assert_equal %w[ClassIII], private_slots.second.skills.pluck(:name)

    get edit_slots_work_day_url(work_day)
    assert_response :success
    assert_select "input[name='slots[#{sara_slots.first.id}][]'][value='#{skills["ClassIII"].id}'][checked]", count: 0
    assert_select "input[name='slots[#{sara_slots.first.id}][]'][value='#{skills["Busguide"].id}'][checked]", count: 1
    assert_select "input[name='slots[#{pm_slots.first.id}][]'][value='#{skills["Computer"].id}'][checked]", count: 1
    assert_select "input[name='slots[#{private_slots.first.id}][]'][value='#{skills["Elite"].id}'][checked]", count: 1
    assert_select "input[name='slots[#{private_slots.second.id}][]'][value='#{skills["Elite"].id}'][checked]", count: 0

    patch update_all_location_slots_url,
      params: { slots: { sara_slots.first.id.to_s => [skills["ClassIV"].id.to_s] } }
    get edit_slots_work_day_url(work_day)
    assert_select "input[name='slots[#{sara_slots.first.id}][]'][value='#{skills["Busguide"].id}'][checked]", count: 0

    patch update_all_location_slots_url,
      params: { slots: { pm_slots.second.id.to_s => [""] } }
    assert_empty pm_slots.second.reload.skills
  end

  test "requirements page guides operator when there are no guide slots" do
    user = User.create!(name: "Requirements admin", email: "requirements-admin@example.test",
      password: "password123", role: :admin)
    sign_in user
    work_day = WorkDay.create!(date: Date.current + 3.days)

    get edit_slots_work_day_url(work_day)

    assert_response :success
    assert_select "div[role='status']", text: /Aún no hay puestos de guías/
    assert_select "a[href='#{locations_work_day_path(work_day)}']", text: "Definir guías por salida"
    assert_select "form[action='#{update_all_location_slots_path}']", count: 0

    work_day.location_slots.create!(location: "Balsa")
    get edit_slots_work_day_url(work_day)

    assert_response :success
    assert_select "h3", text: "Balsa"
    assert_select "strong", text: "Puesto 1"
    assert_select "form[action='#{update_all_location_slots_path}']", count: 1
  end

  test "generated Sara shortage is visible and cannot be published" do
    user = User.create!(name: "Pending Sara admin",
      email: "pending-sara-admin@example.test",
      password: "password123", role: :admin)
    sign_in user
    class_iv = Skill.find_or_create_by!(name: "ClassIV")
    day = WorkDay.create!(date: Date.current + 35.days)
    day.location_slots.create!(location: "Sara-3&4").skills << class_iv

    patch generate_roles_work_day_url(day)

    assert_redirected_to work_day_url(day)
    assert_match(/puestos pendientes/, flash[:notice])
    assert day.reload.generated?

    get work_day_url(day)
    assert_response :success
    assert_select "#day-pending-slots", text: /Sara-3&4: falta 1 puesto por cubrir/
    assert_select "input[type='submit'][value='Publicar programación'][disabled]", count: 1

    post publish_work_day_url(day)
    assert_redirected_to work_day_url(day)
    assert_match(/Asignaciones incompletas por salida/, flash[:alert])
    assert day.reload.generated?
  end

  test "operator fills a pending Sara slot from the operation screen" do
    operator = User.create!(name: "Sara schedule operator",
      email: "sara-schedule-operator@example.test",
      password: "password123", role: :operador)
    sign_in operator
    class_iv = Skill.find_or_create_by!(name: "ClassIV")
    residence = Skill.find_or_create_by!(name: "address_Sarapiqui")
    reserve = Guide.create!(name: "Reserve from operation", priority: 6,
      active: true, pay_category: "freelance_regular",
      skills: [class_iv, residence])
    day = WorkDay.create!(date: Date.current + 46.days, status: :generated)
    slot = day.location_slots.create!(location: "Sara-3&4")
    slot.skills << class_iv

    get work_day_url(day)
    assert_response :success
    assert_select "a[href='#{sara_operation_work_day_path(day)}']", text: "Completar Sara y PM"

    get sara_operation_work_day_url(day)
    assert_response :success
    assert_select "h1", text: "Sara 3 y 4 y PM"
    assert_select "#day-sara-pending-assignments", text: /Reserve from operation/
    assert_select "form[action='#{assign_sara_guide_work_day_path(day)}']", count: 1

    post assign_sara_guide_work_day_path(day),
      params: { slot_id: slot.id, guide_id: reserve.id }

    assert_redirected_to sara_operation_work_day_url(day)
    assert_equal "Sara-3&4", day.guide_days.find_by!(guide: reserve).location
    assert_empty day.roll_coverage_errors

    get sara_operation_work_day_url(day)
    assert_response :success
    assert_select "#day-extra-bus-guides", count: 0
    get work_day_url(day)
    assert_response :success
    assert_select "#day-extra-bus-guides", count: 0
  end

  test "Sara operation accepts drafts but stays restricted to authorized roles" do
    day = WorkDay.create!(date: Date.current + 47.days)
    admin = User.create!(name: "Sara operation admin",
      email: "sara-operation-admin@example.test",
      password: "password123", role: :admin)
    sign_in admin

    get sara_operation_work_day_url(day)
    assert_response :success
    assert_select "#sara-priority-five-availability", count: 1
    assert_select "#day-sara-pending-assignments", count: 0

    day.update!(status: :generated)
    sign_out admin
    accountant = User.create!(name: "Sara operation accountant",
      email: "sara-operation-accountant@example.test",
      password: "password123", role: :contabilidad)
    sign_in accountant

    get sara_operation_work_day_url(day)
    assert_redirected_to root_path
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

  test "published operation lists a guide in Sara and PM on the same day" do
    user = User.create!(name: "Second outing admin",
      email: "second-outing-admin@example.test",
      password: "password123", role: :admin)
    sign_in user
    guide = Guide.create!(name: "Second outing guide", priority: 3,
      active: true, pay_category: "freelance_regular")
    day = WorkDay.create!(date: Date.current + 25.days, status: :published)
    guide_day = day.guide_days.find_by!(guide: guide)
    guide_day.update!(status: :worked, location: "Sara-3&4",
      role_primary: "River Guide")
    pm = day.departures.create!(label: "PM", location: "PM",
      starts_at: Departure.fixed_start_for(day.date, "PM"))
    pm.compensation_assignments.create!(guide: guide, role_code: "river_guide")

    get work_day_path(day)

    assert_response :success
    assert_select "tr.location-sara td", text: "Second outing guide", count: 1
    assert_select "tr.location-pm td", text: "Second outing guide", count: 1
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
    public_link = css_select("a").find { |link| link.text == "Distribución de guías y choferes" }
    assert public_link
    assert_match %r{\A/programacion/[^/]+/distribucion\z}, public_link["href"]

    get distribution_work_day_path(day)
    assert_response :success
    assert_select "h1", "Distribución de guías y choferes"
    assert_select "button[data-copy-distribution]", text: "Copiar enlace", count: 1
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

    sign_out user
    get public_link["href"]
    assert_response :success
    assert_select "h1", "Distribución de guías y choferes"
    assert_select "tr[data-section='Balsa'][data-person-kind='driver']", text: /Distribution driver/
    assert_select "button[data-copy-distribution]", text: "Copiar enlace", count: 1
    assert_select "nav.roll-header__nav", count: 0
    assert_select "a[href='#{work_day_path(day)}']", count: 0
    assert_match(/no-store/, response.headers["Cache-Control"])
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
    assert_equal "no-referrer", response.headers["Referrer-Policy"]

    get public_work_day_distribution_path(token: "invalid")
    assert_response :not_found

    travel 8.days do
      get public_link["href"]
      assert_response :not_found
    end

    day.update_columns(status: WorkDay.statuses.fetch("generated"))
    get public_link["href"]
    assert_response :not_found

    get distribution_work_day_path(day)
    assert_redirected_to new_user_session_path
  end
end
