require "digest"
require "openssl"
require "openssl"
require "openssl"

class WeatherReportImportsController < ActionController::API
  before_action :authenticate_sync_token!

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

  def authenticate_sync_token!
    expected = ENV["WEATHER_REPORT_SYNC_TOKEN"].presence ||
      OpenSSL::HMAC.hexdigest(
        "SHA256",
        Rails.application.credentials.secret_key_base,
        "weather-report-sync-v1"
      )
    provided = request.authorization.to_s.delete_prefix("Bearer ")

    authenticated = expected.present? &&
      provided.present? &&
      ActiveSupport::SecurityUtils.secure_compare(
        Digest::SHA256.hexdigest(provided),
        Digest::SHA256.hexdigest(expected)
      )

    return if authenticated

    render json: { error: "Unauthorized" }, status: :unauthorized
  end
end
