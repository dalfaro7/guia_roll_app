require "test_helper"

class WorkDaysPublicIconsTest < ActionDispatch::IntegrationTest
  test "published distribution shows distinct role icons beside readable labels" do
    roles = [
      ["Boat guide", "River Guide", nil],
      ["Photo guide", "Photographer", nil],
      ["Kayak guide", "Safety Kayaker", nil],
      ["HG guide", "River Guide", "Head Guide"],
      ["TL guide", "River Guide", "Tour Leader"],
      ["Bus guide", "River Guide", "Bus Guide & Towels"]
    ]
    guides = roles.map do |name, _, _|
      Guide.create!(name: name, priority: 3, active: true)
    end
    day = WorkDay.create!(date: Date.current + 1.day, status: :published)
    guides.zip(roles).each do |guide, (_, primary, secondary)|
      day.guide_days.find_by!(guide: guide).update_columns(
        status: GuideDay.statuses.fetch("worked"), location: "Balsa",
        role_primary: primary, role_secondary: secondary)
    end
    company = TransportCompany.create!(name: "Icon transport")
    driver = Driver.create!(name: "Icon driver", transport_company: company)
    bus = Bus.create!(transport_company: company, alias: "Icon bus",
      plate: "IC-101", capacity: 20)
    BusAssignment.create!(bus: bus, driver: driver, work_day: day,
      location: "Balsa", seats_assigned: 0)

    get public_work_day_distribution_path(
      token: day.signed_id(purpose: :public_distribution, expires_in: 7.days))

    assert_response :success
    %w[photographer kayaker boat head-guide tour-leader driver bus-guide].each do |kind|
      assert_select "[data-role-icon='#{kind}'][aria-hidden='true']", minimum: 1
    end
    assert_select "[data-role-icon='boat'] img[src='/icons/guide-helmet-vest.svg']", minimum: 1
    assert_select "[data-role-icon='driver'] img[src='/icons/steering-wheel.svg']", minimum: 1
    assert_select "[data-role-icon='kayaker']", text: "🚣"
    assert_select "tr[data-person-kind='guide']", text: /Photo guide.*Fotógrafo/
    assert_select "tr[data-person-kind='guide']", text: /HG guide.*HG \(Head Guide\)/
    assert_select "tr[data-person-kind='guide']", text: /TL guide.*TL \(Tour Líder\)/
    assert_select "tr[data-person-kind='driver']", text: /Icon driver.*Chofer/
  end
end
