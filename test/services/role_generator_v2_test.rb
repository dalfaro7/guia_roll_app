require "test_helper"

class RoleGeneratorV2Test < ActiveSupport::TestCase
  setup do
    @skills = %w[ClassIII ClassIV Busguide Computer].index_with do |name|
      Skill.find_or_create_by!(name: name)
    end
    @skills["Roll de Sara"] = Skill.find_or_create_by!(name: "Roll de Sara")
  end

  test "specialist covers Sara first, priority one keeps Sara, and level five fills Sara and PM" do
    oso = guide("Priority one Sara", 1, %w[ClassIV])
    specialist = guide("Bus specialist without Sara roll", 2,
      %w[ClassIV Busguide Computer])
    sara_one = guide("Sara roll one", 5, ["ClassIV", "Roll de Sara"])
    sara_two = guide("Sara roll two", 5, ["ClassIV", "Roll de Sara"])
    balsa = guide("Balsa guide", 2, %w[ClassIII])
    excluded = guide("Balsa guide with Class IV", 3, %w[ClassIV])
    reserve = guide("Manual reserve", 6, ["ClassIV", "Roll de Sara"])
    day = WorkDay.create!(date: Date.current + 30.days)
    slot(day, "Sara-3&4", %w[ClassIV Busguide Computer])
    slot(day, "Sara-3&4", %w[ClassIV])
    slot(day, "PM", %w[ClassIV])
    slot(day, "Balsa", %w[ClassIII])

    day.generate_roles!

    assert day.reload.generated?
    assert_equal "Sara-3&4", day.guide_days.find_by!(guide: specialist).location
    assert_equal "Sara-3&4", day.guide_days.find_by!(guide: oso).location
    assert_equal "PM", day.guide_days.find_by!(guide: sara_one).location
    assert day.guide_days.find_by!(guide: sara_two).standby?
    assert_equal "Balsa", day.guide_days.find_by!(guide: balsa).location
    assert day.guide_days.find_by!(guide: excluded).standby?
    assert day.guide_days.find_by!(guide: reserve).standby?
  end

  test "level five Sara guide can cover a specialized post when no existing specialist is available" do
    without_sara_roll = guide("No Sara roll", 5, %w[ClassIV Busguide Computer])
    eligible = guide("Sara specialist", 5,
      ["ClassIV", "Busguide", "Computer", "Roll de Sara"])
    day = WorkDay.create!(date: Date.current + 31.days)
    slot(day, "Sara-3&4", %w[ClassIV Busguide Computer])

    day.generate_roles!

    assert day.guide_days.find_by!(guide: without_sara_roll).standby?
    assert_equal "Sara-3&4", day.guide_days.find_by!(guide: eligible).location
  end

  test "ordinary Sara post does not take a Balsa guide without Sara roll" do
    balsa = guide("Balsa Class IV guide", 2, %w[ClassIV])
    day = WorkDay.create!(date: Date.current + 32.days)
    slot(day, "Sara-3&4", %w[ClassIV])

    assert_raises(RuntimeError) { day.generate_roles! }

    assert day.reload.draft?
    assert day.guide_days.find_by!(guide: balsa).standby?
  end

  private

  def guide(name, priority, skill_names)
    Guide.create!(name: name, priority: priority, active: true,
      pay_category: "freelance_regular", skills: skill_names.map { |skill| @skills.fetch(skill) })
  end

  def slot(day, location, skill_names)
    day.location_slots.create!(location: location).tap do |location_slot|
      location_slot.skills = skill_names.map { |name| @skills.fetch(name) }
    end
  end
end
