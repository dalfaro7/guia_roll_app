require "test_helper"

class Whatsapp::RollNotificationSenderTest < ActiveSupport::TestCase
  FakeResult = Struct.new(:success?, :status, :body)

  class FakeClient
    attr_reader :arguments

    def send_template(**arguments)
      @arguments = arguments
      FakeResult.new(true, 200, { "messages" => [{ "id" => "wamid.roll" }] })
    end
  end

  test "sends the formatted roll to the configured recipient" do
    work_day = WorkDay.create!(date: Date.current + 1.day, status: :published)
    client = FakeClient.new

    with_env("WHATSAPP_ROLL_RECIPIENT", "+506 7296 9810") do
      Whatsapp::RollNotificationSender.send_work_day(work_day, client: client)
    end

    assert_equal "+506 7296 9810", client.arguments[:to]
    assert_equal "nuevo_roll_publicado", client.arguments[:template_name]
    assert_equal "en", client.arguments[:language_code]
    assert_includes client.arguments.dig(:components, 0, :parameters, 0, :text), work_day.date.year.to_s
  end

  test "skips delivery when the recipient is not configured" do
    work_day = WorkDay.create!(date: Date.current + 1.day, status: :published)
    client = FakeClient.new

    with_env("WHATSAPP_ROLL_RECIPIENT", nil) do
      assert_nil Whatsapp::RollNotificationSender.send_work_day(work_day, client: client)
    end
    assert_nil client.arguments
  end

  private

  def with_env(name, value)
    previous = ENV[name]
    value.nil? ? ENV.delete(name) : ENV[name] = value
    yield
  ensure
    previous.nil? ? ENV.delete(name) : ENV[name] = previous
  end
end
