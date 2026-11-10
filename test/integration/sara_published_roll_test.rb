require "test_helper"

class SaraPublishedRollTest < ActionDispatch::IntegrationTest
  setup do
    @hg = User.create!(name: "HG published", email: "published-hg@example.test",
      password: "password123", role: :hg_sarapiqui)
    sign_in @hg
  end

  test "only today and tomorrow published rolls are linked and accessible" do
    today = WorkDay.create!(date: Date.current, status: :published)
    tomorrow = WorkDay.create!(date: Date.tomorrow, status: :published)
    later = WorkDay.create!(date: Date.tomorrow + 1.day, status: :published)
    get sara_work_days_path
    [today, tomorrow].each do |day|
      assert_select "a[href='#{sara_published_work_day_path(day)}']", count: 1
      get sara_published_work_day_path(day)
      assert_response :success
      assert_select "main strong", text: "Publicado"
      assert_select "main form", count: 0
      get sara_work_days_path
    end
    assert_select "a[href='#{sara_published_work_day_path(later)}']", count: 0
    get sara_published_work_day_path(later)
    assert_response :not_found
    %i[draft generated].each do |state|
      tomorrow.update!(status: state)
      get sara_work_days_path
      assert_select "a[href='#{sara_published_work_day_path(tomorrow)}']", count: 0
      get sara_published_work_day_path(tomorrow)
      assert_response :not_found
    end
  end

  test "published roll shows Sara and PM including freelance but not other outings or accounting" do
    day = WorkDay.create!(date: Date.tomorrow)
    [["Sara visible", "Sara-3&4", 5], ["Freelance PM visible", "PM", 6],
      ["Balsa private", "Balsa", 2], ["Private outing", "Privado", 2]].each do |name, location, priority|
      guide = Guide.create!(name: name, priority: priority, active: true)
      day.guide_days.create!(guide: guide, status: :worked,
        location: location, role_primary: "River Guide")
    end
    day.update!(status: :published)
    get sara_published_work_day_path(day)
    assert_response :success
    assert_select "#published-sara", text: /Sara visible/
    assert_select "#published-pm", text: /Freelance PM visible/
    assert_select "main", text: /Balsa private|Private outing/, count: 0
    assert_select "main form", count: 0
    assert_select "a[href='#{work_day_compensation_path(day)}']", count: 0
    day.update!(status: :generated)
    get sara_published_work_day_path(day)
    assert_response :not_found
  end

  test "published transport shows only Sara and PM vehicles and drivers without prices" do
    day = WorkDay.create!(date: Date.tomorrow, status: :published)
    company = TransportCompany.create!(name: "Published transport", internal_fleet: true,
      vehicle_categories: %w[bus_small bus_large four_by_four])
    %w[Sara-3&4 PM Balsa Privado].each_with_index do |location, index|
      bus = Bus.create!(alias: "Vehicle #{location}", plate: "PUB-#{index}",
        capacity: 15, transport_company: company)
      driver = Driver.create!(name: "Driver #{location}", active: true, payment_mode: "none") unless location == "PM"
      day.bus_assignments.create!(bus: bus, driver: driver, location: location,
        seats_assigned: 2)
    end
    get sara_published_work_day_path(day)
    assert_response :success
    assert_select "#published-sara", text: /Vehicle Sara-3&4/
    assert_select "#published-sara", text: /Driver Sara-3&4/
    assert_select "#published-pm", text: /Vehicle PM/
    assert_select "#published-pm", text: /Por asignar/
    assert_select "main", text: /Vehicle Balsa|Driver Balsa|Vehicle Privado|Driver Privado/, count: 0
    assert_select "main", text: /Costo|Tarifa|Pago|USD/, count: 0
  end

  test "unauthorized general role cannot open published Sara" do
    day = WorkDay.create!(date: Date.tomorrow, status: :published)
    @hg.update!(role: :recursos_humanos)
    get sara_published_work_day_path(day)
    assert_redirected_to root_path
  end
end
