require "test_helper"

class Whatsapp::RollNotificationSenderTest < ActiveSupport::TestCase
  FakeResult = Struct.new(:success?, :status, :body)

  class FakeClient
    attr_reader :arguments, :upload_arguments

    def upload_media(**arguments)
      @upload_arguments = arguments
      FakeResult.new(true, 200, { "id" => "media.roll-pdf" })
    end

    def send_template(**arguments)
      @arguments = arguments
      FakeResult.new(true, 200, { "messages" => [{ "id" => "wamid.roll" }] })
    end
  end

  test "sends one flexible parameter to the configured recipient" do
    work_day = WorkDay.create!(date: Date.current + 1.day, status: :published)
    client = FakeClient.new

    with_env("WHATSAPP_ROLL_RECIPIENT", "+506 7296 9810") do
      Whatsapp::RollNotificationSender.send_work_day(work_day, client: client)
    end

    assert_equal "+506 7296 9810", client.arguments[:to]
    assert_equal "nuevo_roll_publicado", client.arguments[:template_name]
    assert_equal "en", client.arguments[:language_code]
    parameters = client.arguments.dig(:components, 0, :parameters)
    assert_equal 1, parameters.length
    assert_no_match(/[\r\n\t]/, parameters.first[:text])
  end

  test "skips delivery when the recipient is not configured" do
    work_day = WorkDay.create!(date: Date.current + 1.day, status: :published)
    client = FakeClient.new

    with_env("WHATSAPP_ROLL_RECIPIENT", nil) do
      assert_nil Whatsapp::RollNotificationSender.send_work_day(work_day, client: client)
    end
    assert_nil client.arguments
  end

  test "uploads and sends a document when the document template is configured" do
    date = Date.current + 1.day
    work_day = WorkDay.create!(date: date, status: :published)
    client = FakeClient.new

    with_env("WHATSAPP_ROLL_RECIPIENT", "+506 7296 9810") do
      with_env("WHATSAPP_ROLL_DOCUMENT_TEMPLATE_NAME", "guide_schedule_pdf") do
        Whatsapp::RollNotificationSender.send_work_day(work_day, client: client)
      end
    end

    assert_equal "guide_schedule_#{date.iso8601}.pdf", client.upload_arguments[:filename]
    assert client.upload_arguments[:io].string.start_with?("%PDF")
    assert_equal "guide_schedule_pdf", client.arguments[:template_name]
    header = client.arguments.dig(:components, 0, :parameters, 0)
    assert_equal "document", header[:type]
    assert_equal "media.roll-pdf", header.dig(:document, :id)
    assert_equal date.strftime("%A, %B %-d, %Y"),
      client.arguments.dig(:components, 1, :parameters, 0, :text)
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
