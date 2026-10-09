require "base64"
require "openssl"

class WeatherReportImportsController < ActionController::API
  SIGNATURE_TOLERANCE = 5.minutes

  before_action :authenticate_signature!

  def create
    reports = Array.wrap(params[:reports].presence || params[:report])

    if reports.empty?
      render json: { error: "No reports supplied" },
             status: :unprocessable_entity
      return
    end

    imported = WeatherReport.transaction do
      reports.map { |report| import_report!(report) }
    end

    render json: {
      imported: imported.size,
      ids: imported.map(&:id)
    }, status: :ok
  rescue KeyError, ActiveRecord::RecordInvalid => error
    render json: { error: error.message }, status: :unprocessable_entity
  end

  private

  def import_report!(raw_report)
    parameters = if raw_report.is_a?(ActionController::Parameters)
      raw_report
    else
      ActionController::Parameters.new(raw_report.to_h)
    end

    attributes = parameters.permit(
      :source_uid,
      :title,
      :body,
      :reported_at,
      :source_name,
      :source_url
    ).to_h

    report = WeatherReport.find_or_initialize_by(
      source_uid: attributes.fetch("source_uid")
    )
    report.assign_attributes(attributes)
    report.save!
    report
  end

  def authenticate_signature!
    timestamp = Integer(
      request.headers["X-Weather-Report-Timestamp"],
      exception: false
    )
    signature = Base64.strict_decode64(
      request.headers["X-Weather-Report-Signature"].to_s
    )

    fresh = timestamp.present? &&
      (Time.current.to_i - timestamp).abs <= SIGNATURE_TOLERANCE
    authenticated = fresh && public_key.verify(
      OpenSSL::Digest::SHA256.new,
      signature,
      "#{timestamp}.#{request.raw_post}"
    )

    return if authenticated

    render json: { error: "Unauthorized" }, status: :unauthorized
  rescue ArgumentError, OpenSSL::PKey::PKeyError
    render json: { error: "Unauthorized" }, status: :unauthorized
  end

  def public_key
    path = ENV.fetch(
      "WEATHER_REPORT_SYNC_PUBLIC_KEY_PATH",
      Rails.root.join("config/weather_report_sync_public.pem").to_s
    )
    OpenSSL::PKey::RSA.new(File.read(path))
  end
end
