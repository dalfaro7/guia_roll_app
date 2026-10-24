require "test_helper"

class OfficeDayOffGeneratorTest < ActiveSupport::TestCase
  setup do
    OfficeEmployee.update_all(active: false)
    @fiorela = OfficeEmployee.create!(name: "Fiorela Mena", active: true, department: "office")
    @manuel = OfficeEmployee.create!(name: "Manuel Anchia", active: true, department: "office")
    @month = Date.new(2026, 11, 1)
  end

  def dates(employee)
    employee.office_employee_days.day_off.order(:date).pluck(:date)
  end

  test "Fiorela cannot rest on Wednesdays or the 15th and 30th" do
    [Date.new(2026,11,4), Date.new(2026,11,15), Date.new(2026,11,30)].each do |date|
      assert @fiorela.cannot_take_day_off_on?(date)
    end
    assert_not @fiorela.cannot_take_day_off_on?(Date.new(2026,11,14))
  end

  test "new days match including weekends and respect restrictions" do
    OfficeDays::DayOffGenerator.new(month: @month).call
    assert_equal dates(@fiorela), dates(@manuel)
    assert_equal 6, dates(@fiorela).size
    assert dates(@fiorela).any? { |d| d.month == 11 && d.saturday? }
    assert dates(@fiorela).any? { |d| d.month == 11 && d.sunday? }
    assert dates(@fiorela).none? { |d| d.wednesday? || [15,30].include?(d.day) }
    before = OfficeEmployeeDay.order(:id).map(&:attributes)
    OfficeDays::DayOffGenerator.new(month: @month).call
    assert_equal before, OfficeEmployeeDay.order(:id).map(&:attributes)
  end

  test "existing first week stays unchanged even when dates differ" do
    f = OfficeEmployeeDay.create!(office_employee: @fiorela, date: Date.new(2026,10,30), status: :day_off, day_off_source: "manual")
    m = OfficeEmployeeDay.create!(office_employee: @manuel, date: Date.new(2026,10,26), status: :day_off, day_off_source: "automatic")
    before = [f.attributes, m.attributes]
    OfficeDays::DayOffGenerator.new(month: @month).call
    assert_equal before, [f.reload.attributes, m.reload.attributes]
    assert_equal 2, OfficeEmployeeDay.where(date: Date.new(2026,10,26)..Date.new(2026,11,1)).count
    assert_equal dates(@fiorela).drop(1), dates(@manuel).drop(1)
  end

  test "either existing free day preserves the whole week" do
    OfficeEmployeeDay.create!(office_employee: @manuel, date: Date.new(2026,11,10), status: :day_off)
    OfficeDays::DayOffGenerator.new(month: @month).call
    assert_empty @fiorela.office_employee_days.where(date: Date.new(2026,11,9)..Date.new(2026,11,15))
  end

  test "pair avoids holidays and another colleague from their department" do
    colleague = OfficeEmployee.create!(name: "Colleague", active: false, department: "office")
    OfficeEmployeeDay.create!(office_employee: colleague, date: Date.new(2026,11,7), status: :day_off)
    OfficeHoliday.create!(name: "Test holiday", date: Date.new(2026,11,8), double_pay: false)
    OfficeDays::DayOffGenerator.new(month: @month).call
    assert_equal dates(@fiorela), dates(@manuel)
    assert_not_includes dates(@fiorela), Date.new(2026,11,7)
    assert_not_includes dates(@fiorela), Date.new(2026,11,8)
  end

  test "blocked dates for Manuel cannot become Fiorela free days" do
    (Date.new(2026,11,2)..Date.new(2026,11,8)).each do |date|
      OfficeEmployeeDay.create!(office_employee: @manuel, date: date, status: :vacation)
    end
    OfficeDays::DayOffGenerator.new(month: @month).call
    assert_empty @fiorela.office_employee_days.where(date: Date.new(2026,11,2)..Date.new(2026,11,8))
  end
end
