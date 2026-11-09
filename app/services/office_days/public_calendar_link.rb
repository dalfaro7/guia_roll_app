module OfficeDays
  class PublicCalendarLink
    PURPOSE = "office-day-off-calendar-v1"

    def self.generate(employee:, month:)
      encryptor.encrypt_and_sign(
        { "employee_id" => employee.id, "month" => month.strftime("%Y-%m") },
        purpose: PURPOSE
      )
    end

    def self.read(token)
      encryptor.decrypt_and_verify(token, purpose: PURPOSE)
    rescue ActiveSupport::MessageEncryptor::InvalidMessage, ArgumentError
      nil
    end

    def self.encryptor
      key = Rails.application.key_generator.generate_key(PURPOSE, 32)
      ActiveSupport::MessageEncryptor.new(key, cipher: "aes-256-gcm", serializer: JSON, url_safe: true)
    end
    private_class_method :encryptor
  end
end
