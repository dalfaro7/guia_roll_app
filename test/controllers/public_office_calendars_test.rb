require "test_helper"

class PublicOfficeCalendarsTest < ActionDispatch::IntegrationTest
  setup do
    @employee = OfficeEmployee.create!(name: "Empleado compartido", active: true)
    @other = OfficeEmployee.create!(name: "Empleado privado", active: true)
    @month = Date.new(2026, 11, 1)
    @token = OfficeDays::PublicCalendarLink.generate(employee: @employee, month: @month)
    @employee.office_employee_days.create!(date: @month + 7, status: :day_off, notes: "NOTA PRIVADA")
    @employee.office_employee_days.create!(date: @month + 9, status: :sick_leave, notes: "SALUD PRIVADA")
    @employee.office_employee_days.create!(date: @month - 1, status: :day_off)
    @other.office_employee_days.create!(date: @month + 7, status: :day_off)
  end

  test "anonymous link exposes only selected employee month and days off" do
    assert_no_difference "OfficeEmployeeDay.count" do
      get public_office_calendar_path(token: @token), params: { month: "2026-10", office_employee_id: @other.id }
    end
    assert_response :success
    assert_select "h1", "Días libres de Empleado compartido"
    assert_select "td.free", count: 1
    assert_select "li", count: 1
    assert_select "a, form, button", count: 0
    ["Empleado privado", "NOTA PRIVADA", "SALUD PRIVADA"].each { |text| assert_not_includes response.body, text }
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal "no-referrer", response.headers["Referrer-Policy"]
  end

  test "invalid and altered tokens fail closed" do
    ["123", @token.reverse].each do |token|
      get public_office_calendar_path(token: token)
      assert_response :not_found
    end
  end

  test "empty month has explicit message" do
    token = OfficeDays::PublicCalendarLink.generate(employee: @employee, month: Date.new(2027, 1, 1))
    get public_office_calendar_path(token: token)
    assert_response :success
    assert_includes response.body, "No hay días libres registrados para este mes."
  end

  test "hr and admin can copy scoped link and retain employee when changing month" do
    %i[recursos_humanos admin].each do |role|
      user = User.create!(name: role.to_s, email: "share-#{role}@example.com", password: "password123", role: role)
      sign_in user
      get office_employee_days_path, params: { month: "2026-11", office_employee_id: @employee.id }
      assert_response :success
      imports = JSON.parse(Nokogiri::HTML(response.body).at_css('script[type="importmap"]').text).fetch("imports")
      assert_match(/@popperjs--core/, imports.fetch("@popperjs/core"))
      assert_select "script[src*=office_calendar_copy][defer]"
      assert_select "button[data-office-share-copy]"
      assert_select "input#public-office-calendar-url[readonly]", count: 1
      assert_select "button", text: "Copiar enlace"
      assert_select "input[type=hidden][name=office_employee_id][value='#{@employee.id}']"
      get office_employee_days_path, params: { month: "2026-11" }
      assert_select "input#public-office-calendar-url", count: 0
      sign_out user
    end
  end

  test "anonymous and operator cannot obtain links from private calendar" do
    get office_employee_days_path, params: { office_employee_id: @employee.id }
    assert_redirected_to new_user_session_path
    user = User.create!(name: "Operator", email: "share-operator@example.com", password: "password123", role: :operador)
    sign_in user
    get office_employee_days_path, params: { office_employee_id: @employee.id }
    assert_redirected_to root_path
  end
end
