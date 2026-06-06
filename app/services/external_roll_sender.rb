# app/services/external_roll_sender.rb

require "net/http"
require "json"

class ExternalRollSender
  API_URL = "https://arenalrafting.photos/api/rolls"

  def self.send_work_day(work_day)
    guide_names = work_day.guide_days
                          .where(status: [:worked, :standby])
                          .includes(:guide)
                          .map { |guide_day| guide_day.guide.name }
                          .join(",")

    payload = {
      work_day_id: work_day.id,
      date: work_day.date,
      guides: guide_names
    }

    uri = URI(API_URL)

    response = Net::HTTP.post(
      uri,
      payload.to_json,
      {
        "Content-Type" => "application/json"
        # "Authorization" => "Bearer TU_TOKEN_AQUI"
      }
    )

    Rails.logger.info "External roll response: #{response.code} - #{response.body}"

    response
  rescue => e
    Rails.logger.error "Error sending work day to external system: #{e.message}"
    nil
  end
end