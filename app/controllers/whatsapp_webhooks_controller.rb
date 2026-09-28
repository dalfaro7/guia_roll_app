require "openssl"

class WhatsappWebhooksController < ActionController::API
  def verify
    if params["hub.mode"] == "subscribe" && valid_verify_token?
      render plain: params["hub.challenge"], status: :ok
    else
      head :forbidden
    end
  end

  def receive
    return head :unauthorized unless valid_signature?

    payload = JSON.parse(request.raw_post)

    Rails.logger.info(
      "[WHATSAPP WEBHOOK] object=#{payload['object']} " \
      "entries=#{Array(payload['entry']).size}"
    )

    head :ok
  rescue JSON::ParserError
    head :bad_request
  end

  private

  def valid_verify_token?
    secure_match(
      params["hub.verify_token"].to_s,
      ENV.fetch("WHATSAPP_WEBHOOK_VERIFY_TOKEN", "")
    )
  end

  def valid_signature?
    app_secret = ENV.fetch("META_APP_SECRET", "")
    return false if app_secret.blank?

    expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', app_secret, request.raw_post)}"

    secure_match(
      request.headers["X-Hub-Signature-256"].to_s,
      expected
    )
  end

  def secure_match(received, expected)
    return false if received.blank? || expected.blank?
    return false unless received.bytesize == expected.bytesize

    ActiveSupport::SecurityUtils.secure_compare(received, expected)
  end
end
