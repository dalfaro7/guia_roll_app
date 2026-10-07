require "test_helper"

class Whatsapp::RollDocumentFormatterTest < ActiveSupport::TestCase
  test "keeps every guide in a separate row when a location has twenty guides" do
    guides = 20.times.map do |index|
      Guide.create!(name: format("Balsa Guide %02d", index + 1), priority: 2, active: true)
    end
    work_day = WorkDay.create!(date: Date.new(2026, 10, 7), status: :published)
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
end
