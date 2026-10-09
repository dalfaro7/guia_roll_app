require "test_helper"

class Whatsapp::RollDocumentFormatterTest < ActiveSupport::TestCase
  test "keeps every guide in a separate row when a location has twenty guides" do
    guides = 20.times.map do |index|
      Guide.create!(name: format("Balsa Guide %02d", index + 1), priority: 2, active: true)
    end
    work_day = WorkDay.create!(date: Date.current + 1.day, status: :published)
    guides.each do |guide|
      work_day.guide_days.find_by!(guide: guide).update!(
        status: :worked,
        location: "Balsa",
        role_primary: "River Guide"
      )
    end

    formatter = Whatsapp::RollDocumentFormatter.new(work_day)
    balsa = formatter.sections.find { |section| section[:title] == "BALSA" }

    assert_equal 20, balsa[:rows].length
    assert_equal (1..20).to_a, balsa[:rows].pluck(:position)
    assert_equal "Balsa Guide 01", balsa[:rows].first[:name]
    assert_equal "Balsa Guide 20", balsa[:rows].last[:name]
  end
test "uses the published fairness order for standby rows" do
  worked_guide = Guide.create!(name: "Alpha Worked", priority: 3, active: true)
  waiting_guide = Guide.create!(name: "Zulu Waiting", priority: 3, active: true)
  [worked_guide, waiting_guide].each do |guide|
    guide.update_columns(
      fairness_started_on: Date.current.beginning_of_month,
      fairness_entry_roll_days: 0
    )
  end

  previous_day = WorkDay.create!(date: Date.current, status: :published)
  previous_day.guide_days.find_by!(guide: worked_guide).update!(
    status: :worked,
    location: "Balsa",
    role_primary: "River Guide"
  )

  work_day = WorkDay.create!(date: Date.current + 1.day, status: :published)
  expected_names = work_day.standby_guides_for_published_roll.map do |guide_day|
    guide_day.guide.name.to_s.strip
  end
  standby = Whatsapp::RollDocumentFormatter.new(work_day)
    .sections
    .find { |section| section[:title] == "STANDBY" }
  actual_names = standby[:rows].pluck(:name)

  assert_equal expected_names, actual_names
  assert_operator actual_names.index("Zulu Waiting"), :<, actual_names.index("Alpha Worked")
end

end
