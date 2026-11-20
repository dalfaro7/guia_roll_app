require "test_helper"

class ExternalRollSenderTest < ActiveSupport::TestCase
  test "sends only river guides belonging to each outing" do
    guide = Struct.new(:name)
    entry = Struct.new(:guide, :location, :role_primary)
    work_day = Struct.new(:id, :date).new(123, Date.new(2026, 11, 20))
    roster = Struct.new(:entries).new([
      entry.new(guide.new("Ana Balsa"), "Balsa", "River Guide"),
      entry.new(guide.new("Luis Sara"), "Sara-4", "River Guide"),
      entry.new(guide.new("Luis Sara"), "PM", "River Guide"),
      entry.new(guide.new("Marta PM"), "PM", "River Guide"),
      entry.new(guide.new("Foto Balsa"), "Balsa", "Photographer"),
      entry.new(guide.new("Privado"), "Privado", "River Guide")
    ])

    original_roster_constructor = RollOutingRoster.method(:new)
    RollOutingRoster.define_singleton_method(:new) { |_day| roster }
    begin
      payloads = ExternalRollSender.payloads_for(work_day).index_by { |item| item[:tour_name] }
      assert_equal %w[rio_balsa rio_sarapiqui rio_sarapiqui_pm], payloads.keys
      assert_equal "Ana Balsa", payloads.fetch("rio_balsa")[:guides]
      assert_equal "Luis Sara", payloads.fetch("rio_sarapiqui")[:guides]
      assert_equal "Luis Sara,Marta PM", payloads.fetch("rio_sarapiqui_pm")[:guides]
    ensure
      RollOutingRoster.define_singleton_method(:new, original_roster_constructor)
    end
  end
end
