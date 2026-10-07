require "stringio"

module Whatsapp
  class RollNotificationSender
    DEFAULT_TEMPLATE_NAME = "nuevo_roll_publicado"
    DEFAULT_LANGUAGE_CODE = "en"

    def self.send_work_day(work_day, client: Client.new)
      recipient = ENV["WHATSAPP_ROLL_RECIPIENT"].to_s
      if recipient.blank?
        Rails.logger.warn("[WHATSAPP ROLL] Envío omitido: falta WHATSAPP_ROLL_RECIPIENT")
        return nil
      end

      document_template_name = ENV["WHATSAPP_ROLL_DOCUMENT_TEMPLATE_NAME"].presence
      return send_document(work_day, recipient, document_template_name, client) if document_template_name

      send_text(work_day, recipient, client)
    rescue => error
      Rails.logger.error(
        "[WHATSAPP ROLL] ERROR enviando WorkDay #{work_day&.id}: " \
        "#{error.class} - #{error.message}"
      )
      nil
    end

    def self.send_text(work_day, recipient, client)
      message = RollMessageFormatter.new(work_day).template_parameter
      result = client.send_template(
        to: recipient,
        template_name: ENV.fetch("WHATSAPP_ROLL_TEMPLATE_NAME", DEFAULT_TEMPLATE_NAME),
        language_code: ENV.fetch("WHATSAPP_ROLL_TEMPLATE_LANGUAGE", DEFAULT_LANGUAGE_CODE),
        components: [
          {
            type: "body",
            parameters: [{ type: "text", text: message }]
          }
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
    end
    private_class_method :send_text

    def self.send_document(work_day, recipient, template_name, client)
      formatter = RollDocumentFormatter.new(work_day)
      filename = "guide_schedule_#{work_day.date.iso8601}.pdf"
      pdf = RollPdfGenerator.new(work_day).render
      upload = client.upload_media(
        io: StringIO.new(pdf),
        filename: filename,
        content_type: "application/pdf"
      )
      unless upload.success?
        Rails.logger.error(
          "[WHATSAPP ROLL] Meta rechazó el PDF de WorkDay #{work_day.id}. " \
          "HTTP #{upload.status}: #{upload.body.inspect}"
        )
        return upload
      end

      media_id = upload.body["id"].to_s
      raise "Meta no devolvió el identificador del PDF" if media_id.blank?

      result = client.send_template(
        to: recipient,
        template_name: template_name,
        language_code: ENV.fetch("WHATSAPP_ROLL_DOCUMENT_TEMPLATE_LANGUAGE", DEFAULT_LANGUAGE_CODE),
        components: [
          {
            type: "header",
            parameters: [
              {
                type: "document",
                document: { id: media_id, filename: filename }
              }
            ]
          },
          {
            type: "body",
            parameters: [{ type: "text", text: formatter.date_label }]
          }
        ]
      )

      if result.success?
        Rails.logger.info("[WHATSAPP ROLL] WorkDay #{work_day.id} enviado con PDF correctamente")
      else
        Rails.logger.error(
          "[WHATSAPP ROLL] Meta rechazó WorkDay #{work_day.id} con PDF. " \
          "HTTP #{result.status}: #{result.body.inspect}"
        )
      end
      result
    end
    private_class_method :send_document
  end
end
