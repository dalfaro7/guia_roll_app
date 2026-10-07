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
      business_account_id: ENV["WHATSAPP_BUSINESS_ACCOUNT_ID"],
      api_version: ENV.fetch("WHATSAPP_GRAPH_API_VERSION", "v25.0"),
      http: nil
    )
      @access_token = access_token.to_s
      @phone_number_id = phone_number_id.to_s
      @business_account_id = business_account_id.to_s
      @api_version = api_version.to_s
      @http = http
    end

    def send_template(to:, template_name:, language_code:, components: nil)
      require_configuration!("WHATSAPP_ACCESS_TOKEN" => @access_token,
                             "WHATSAPP_PHONE_NUMBER_ID" => @phone_number_id)

      recipient = normalize_phone(to)
      raise ArgumentError, "Ingrese un número de destino válido." if recipient.blank?
      raise ArgumentError, "Ingrese el nombre de la plantilla." if template_name.blank?
      raise ArgumentError, "Ingrese el código de idioma." if language_code.blank?

      uri = URI("https://graph.facebook.com/#{@api_version}/#{@phone_number_id}/messages")
      request = Net::HTTP::Post.new(uri)
      authorize(request)
      template = {
        name: template_name,
        language: { code: language_code }
      }
      template[:components] = components if components.present?

      request.body = {
        messaging_product: "whatsapp",
        to: recipient,
        type: "template",
        template: template
      }.to_json

      perform(uri, request)
    end

    def phone_numbers
      require_configuration!("WHATSAPP_ACCESS_TOKEN" => @access_token,
                             "WHATSAPP_BUSINESS_ACCOUNT_ID" => @business_account_id)

      fields = "id,display_phone_number,verified_name,quality_rating,platform_type"
      uri = URI("https://graph.facebook.com/#{@api_version}/#{@business_account_id}/phone_numbers")
      uri.query = URI.encode_www_form(fields: fields)
      request = Net::HTTP::Get.new(uri)
      authorize(request)

      perform(uri, request)
    end

    private

    def require_configuration!(values)
      missing = values.filter_map { |name, value| name if value.blank? }
      return if missing.empty?

      raise ConfigurationError, "Faltan variables de WhatsApp: #{missing.join(', ')}"
    end

    def normalize_phone(value)
      value.to_s.gsub(/\D/, "")
    end

    def authorize(request)
      request["Authorization"] = "Bearer #{@access_token}"
      request["Content-Type"] = "application/json"
    end

    def perform(uri, request)
      response = http_for(uri).request(request)
      status = response.code.to_i

      Result.new(
        success: status.between?(200, 299),
        status: status,
        body: parse_json(response.body)
      )
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
