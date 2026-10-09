require "test_helper"

class WeatherReportTest < ActiveSupport::TestCase
  test "recent returns newest report first" do
    older = create_report("older", 2.hours.ago)
    newer = create_report("newer", 1.hour.ago)

    assert_equal [newer, older], WeatherReport.recent.to_a
  end

  test "source url must be a ChatGPT shared conversation" do
  report = build_report("unsafe-url", 1.hour.ago)
  report.source_url = "javascript:alert(1)"

  assert_not report.valid?
  assert_includes report.errors[:source_url], "must be a ChatGPT shared conversation"
end

test "source uid must be unique" do
    create_report("same", 2.hours.ago)
    duplicate = build_report("same", 1.hour.ago)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:source_uid], "has already been taken"
  end

  private

  def create_report(uid, reported_at)
    build_report(uid, reported_at).tap(&:save!)
  end

  def build_report(uid, reported_at)
    WeatherReport.new(
      source_uid: uid,
      title: "Informe #{uid}",
      body: "Contenido #{uid}",
      reported_at: reported_at,
      source_name: "ChatGPT",
      source_url: "https://chatgpt.com/share/example"
    )
  end
end
