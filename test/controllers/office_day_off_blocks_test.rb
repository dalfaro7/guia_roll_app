require "test_helper"

class OfficeDayOffBlocksTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(name: "Block Admin", email: "block-admin@example.com", password: "password123", role: :admin)
    @date = Date.new(2026, 12, 24)
  end

  test "admin manages global blocks without modifying existing employee days" do
    employee = OfficeEmployee.create!(name: "Existing libre", active: true)
    day = employee.office_employee_days.create!(date: @date, status: :day_off)
    before = day.attributes
    sign_in @admin
    assert_difference "OfficeDayOffBlock.count", 1 do
      post office_day_off_blocks_path, params: { office_day_off_block: { date: @date, reason: "Operación especial", created_by_id: 999 } }
    end
    block = OfficeDayOffBlock.find_by!(date: @date)
    assert_equal @admin, block.created_by
    assert_equal before, day.reload.attributes
    get office_employee_days_path, params: { month: "2026-12" }
    assert_response :success
    assert_includes response.body, "Bloqueado por admin"
    assert_includes response.body, "Administrar fechas bloqueadas"
    assert_difference "OfficeDayOffBlock.count", -1 do
      delete office_day_off_block_path(block)
    end
    assert_equal before, day.reload.attributes
  end

  test "invalid and duplicate dates are rejected" do
    sign_in @admin
    OfficeDayOffBlock.create!(date: @date, created_by: @admin)
    [@date, "", "invalid"].each do |date|
      assert_no_difference "OfficeDayOffBlock.count" do
        post office_day_off_blocks_path, params: { office_day_off_block: { date: date } }
      end
      assert_response :unprocessable_entity
      assert_select "[role=alert]"
    end
  end

  test "hr reads but cannot add or remove blocks; anonymous and operators have no access" do
    block = OfficeDayOffBlock.create!(date: @date, created_by: @admin)
    get office_day_off_blocks_path
    assert_redirected_to new_user_session_path
    %i[recursos_humanos operador].each do |role|
      user = User.create!(name: role.to_s, email: "block-#{role}@example.com", password: "password123", role: role)
      sign_in user
      get office_day_off_blocks_path, params: { month: "2026-12" }
      if role == :recursos_humanos
        assert_response :success
        assert_select "input[type=submit][value='Bloquear fecha']", count: 0
        assert_select "button", text: "Quitar bloqueo", count: 0
      else
        assert_redirected_to root_path
      end
      assert_no_difference "OfficeDayOffBlock.count" do
        post office_day_off_blocks_path, params: { office_day_off_block: { date: @date + 1 } }
        assert_redirected_to root_path
        delete office_day_off_block_path(block)
        assert_redirected_to root_path
      end
      sign_out user
    end
  end

  test "generator excludes blocked weekdays weekends and month boundary dates for everyone" do
    OfficeEmployee.update_all(active: false)
    f = OfficeEmployee.create!(name: "Fiorela Mena", active: true)
    m = OfficeEmployee.create!(name: "Manuel Anchia", active: true)
    other = OfficeEmployee.create!(name: "Other active", active: true)
    month = Date.new(2026, 12, 1)
    range = Date.new(2026, 11, 30)..Date.new(2027, 1, 3)
    blocked = range.select { |d| d.saturday? || d.sunday? || d.day == 1 || d.day == 30 || d.day == 24 }
    generator = OfficeDays::DayOffGenerator.new(month: month)
    blocked.each { |d| OfficeDayOffBlock.create!(date: d, created_by: @admin) }
    generator.call
    assert_equal 0, OfficeEmployeeDay.where(office_employee: [f,m,other], date: blocked).count
    assert_equal f.office_employee_days.order(:date).pluck(:date), m.office_employee_days.order(:date).pluck(:date)
    [f,m,other].each { |e| assert e.office_employee_days.exists? }
  end

  test "fully blocked generation preserves existing rows and credits" do
    OfficeEmployee.update_all(active: false)
    e = OfficeEmployee.create!(name: "Preserved employee", active: true)
    e.office_employee_days.create!(date: @date, status: :day_off, day_off_source: "manual")
    (Date.new(2026,11,30)..Date.new(2027,1,3)).each { |d| OfficeDayOffBlock.create!(date: d, created_by: @admin) }
    before = OfficeEmployeeDay.order(:id).map(&:attributes)
    credits = OfficeDayCredit.order(:id).map(&:attributes)
    OfficeDays::DayOffGenerator.new(month: Date.new(2026,12,1)).call
    assert_equal before, OfficeEmployeeDay.order(:id).map(&:attributes)
    assert_equal credits, OfficeDayCredit.order(:id).map(&:attributes)
  end
end
