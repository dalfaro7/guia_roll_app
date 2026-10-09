require "test_helper"

class Whatsapp::RollPdfGeneratorTest < ActiveSupport::TestCase
  test "renders a valid nonempty PDF" do
    guide = Guide.create!(name: "PDF Guide", priority: 1, active: true)
    work_day = WorkDay.create!(date: Date.current + 1.day, status: :published)
    work_day.guide_days.find_by!(guide: guide).update!(
      status: :worked,
      location: "Balsa",
      role_primary: "River Guide"
    )

    pdf = Whatsapp::RollPdfGenerator.new(work_day).render

    assert pdf.start_with?("%PDF")
    assert_operator pdf.bytesize, :>, 1_000
  end
end
