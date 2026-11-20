require "net/http"
require "json"

class ExternalRollSender
  API_URL = "https://arenalrafting.photos/api/rolls"
  TOUR_LOCATIONS = {
    "rio_balsa" => Departure::OPERATING_SECTIONS.fetch("Balsa"),
    "rio_sarapiqui" => Departure::OPERATING_SECTIONS.fetch("Sara-3&4"),
    "rio_sarapiqui_pm" => Departure::OPERATING_SECTIONS.fetch("PM")
  }.freeze

  def self.payloads_for(work_day)
    entries = RollOutingRoster.new(work_day).entries

    TOUR_LOCATIONS.map do |tour_name, locations|
      names = entries.filter_map do |entry|
        entry.guide.name.strip if entry.role_primary == "River Guide" &&
          locations.include?(entry.location)
      end.uniq.sort

      {
        work_day_id: work_day.id,
        date: work_day.date,
        tour_name: tour_name,
        guides: names.join(",")
      }
    end
  end

  def self.send_work_day(work_day)
    uri = URI(API_URL)
    responses = {}

    payloads_for(work_day).each do |payload|
      tour_name = payload.fetch(:tour_name)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 20

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["Accept"] = "application/json"
      request.body = payload.to_json

      begin
        response = http.request(request)
        responses[tour_name] = response
        level = response.is_a?(Net::HTTPSuccess) ? :info : :error
        Rails.logger.public_send(level,
          "[EXTERNAL ROLL] WorkDay #{work_day.id}, #{tour_name}: HTTP #{response.code}")
      rescue StandardError => error
        responses[tour_name] = nil
        Rails.logger.error(
          "[EXTERNAL ROLL] WorkDay #{work_day.id}, #{tour_name}: #{error.class} - #{error.message}")
      end
    end

    responses
  rescue StandardError => error
    Rails.logger.error(
      "[EXTERNAL ROLL] Error preparando WorkDay #{work_day&.id}: #{error.class} - #{error.message}")
    nil
  end
end
