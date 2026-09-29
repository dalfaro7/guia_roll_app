require "net/http"
require "json"

module Whatsapp
  class Client
    class ConfigurationError < StandardError; end

    Result = Struct.new(:success, :status, :body, keyword_init: true) do
      def success?
        success
      end
    end

    def initialize(
      access_token: ENV["WHATSAPP_ACCESS_TOKEN"],
      phone_number_id: ENV["WHATSAPP_PHONE_NUMBER_ID"],
      api_version: ENV.fetch("WHATSAPP_GRAPH_API_VERSION", "v25.0"),
      http: nil
    )
      @access_token = access_token.to_s
      @phone_number_id = phone_number_id.to_s
      @api_version = api_version.to_s
      @http = http
    end

    def send_template(to:, template_name:, language_code:)
      validate_configuration!

      recipient = normalize_phone(to)
      raise ArgumentError, "Ingrese un número de destino válido." if recipient.blank?
      raise ArgumentError, "Ingrese el nombre de la plantilla." if template_name.blank?
      raise ArgumentError, "Ingrese el código de idioma." if language_code.blank?

      uri = URI("https://graph.facebook.com/#{@api_version}/#{@phone_number_id}/messages")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@access_token}"
      request["Content-Type"] = "application/json"
      request.body = {
        messaging_product: "whatsapp",
        to: recipient,
        type: "template",
        template: {
          name: template_name,
          language: { code: language_code }
        }
      }.to_json

      response = http_for(uri).request(request)
      body = parse_json(response.body)
      status = response.code.to_i

      Result.new(
        success: status.between?(200, 299),
        status: status,
        body: body
      )
    end

    private

    def validate_configuration!
      missing = []
      missing << "WHATSAPP_ACCESS_TOKEN" if @access_token.blank?
      missing << "WHATSAPP_PHONE_NUMBER_ID" if @phone_number_id.blank?
      return if missing.empty?

      raise ConfigurationError, "Faltan variables de WhatsApp: #{missing.join(', ')}"
    end

    def normalize_phone(value)
      value.to_s.gsub(/\D/, "")
    end

    def http_for(uri)
      return @http if @http

      Net::HTTP.new(uri.host, uri.port).tap do |http|
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 20
      end
    end

    def parse_json(body)
      JSON.parse(body.to_s)
    rescue JSON::ParserError
      { "raw" => body.to_s }
    end
  end
end
