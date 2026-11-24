require "test_helper"

class PublicCurrentDistributionTest < ActionDispatch::IntegrationTest
  test "fixed public link shows tomorrow when published and falls back to today" do
    today = Date.current
    current = WorkDay.create!(date: today, status: :published)
    next_day = WorkDay.create!(date: today + 1.day, status: :generated)
    path = public_roll_path

    get path
    assert_response :success
    assert_select "p.distribution-date", text: I18n.l(current.date, format: :long)
    assert_equal public_roll_url,
      css_select("button[data-copy-distribution]").first["data-copy-distribution"]
    assert_match(/no-store/, response.headers["Cache-Control"])
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]

    next_day.update!(status: :published)
    get path
    assert_response :success
    assert_select "p.distribution-date", text: I18n.l(next_day.date, format: :long)
    assert_equal "/roll", path
  end

  test "fixed public link hides unpublished schedules and rejects invalid tokens" do
    WorkDay.create!(date: Date.current + 1.day, status: :generated)
    path = public_roll_path

    get path
    assert_response :success
    assert_select "h1", "Distribución de guías y choferes"
    assert_select "#distribution-table", count: 0
    assert_select "button[data-copy-distribution]", count: 1

    get public_current_distribution_path(token: PublicCurrentDistributionLink.token)
    assert_response :success
    assert_equal public_roll_url,
      css_select("button[data-copy-distribution]").first["data-copy-distribution"]

    get public_current_distribution_path(token: "invalid")
    assert_response :not_found
  end
end
