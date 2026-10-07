module Whatsapp
  class RollNotificationSender
    DEFAULT_TEMPLATE_NAME = "nuevo_roll_publicado"
    DEFAULT_LANGUAGE_CODE = "en_US"

    def self.send_work_day(work_day, client: Client.new)
      recipient = ENV["WHATSAPP_ROLL_RECIPIENT"].to_s
      if recipient.blank?
        Rails.logger.warn("[WHATSAPP ROLL] Envío omitido: falta WHATSAPP_ROLL_RECIPIENT")
        return nil
      end

      message = RollMessageFormatter.new(work_day).call
      result = client.send_template(
        to: recipient,
        template_name: ENV.fetch("WHATSAPP_ROLL_TEMPLATE_NAME", DEFAULT_TEMPLATE_NAME),
        language_code: ENV.fetch("WHATSAPP_ROLL_TEMPLATE_LANGUAGE", DEFAULT_LANGUAGE_CODE),
        components: [
          { type: "body", parameters: [{ type: "text", text: message }] }
        ]
      )

      if result.success?
        Rails.logger.info("[WHATSAPP ROLL] WorkDay #{work_day.id} enviado correctamente")
      else
        Rails.logger.error(
          "[WHATSAPP ROLL] Meta rechazó WorkDay #{work_day.id}. " \
          "HTTP #{result.status}: #{result.body.inspect}"
        )
      end
      result
    rescue => error
      Rails.logger.error(
        "[WHATSAPP ROLL] ERROR enviando WorkDay #{work_day&.id}: " \
        "#{error.class} - #{error.message}"
      )
      nil
    end
  end
end
