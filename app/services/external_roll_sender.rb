# app/services/external_roll_sender.rb

require "net/http"
require "json"

class ExternalRollSender
  API_URL = "https://arenalrafting.photos/api/rolls"

  def self.send_work_day(work_day)
    # ============================================================
    # OBTENER LOS GUÍAS DEL ROLL
    #
    # Solo:
    # - status = worked
    # - role_primary = River Guide
    #
    # Ordenados alfabéticamente.
    # ============================================================
    guide_names =
      work_day
        .guide_days
        .where(
          status: :worked,
          role_primary: "River Guide"
        )
        .joins(:guide)
        .order("guides.name ASC")
        .pluck("guides.name")
        .join(",")

    # ============================================================
    # PAYLOAD QUE RECIBIRÁ TOURFOTOS
    # ============================================================
    payload = {
      work_day_id: work_day.id,
      date: work_day.date,
      guides: guide_names
    }

    Rails.logger.info(
      "[EXTERNAL ROLL] Enviando WorkDay #{work_day.id}"
    )

    Rails.logger.info(
      "[EXTERNAL ROLL] Fecha: #{work_day.date}"
    )

    Rails.logger.info(
      "[EXTERNAL ROLL] Guías: #{guide_names}"
    )

    # ============================================================
    # ENVIAR A TOURFOTOS
    # ============================================================
    uri = URI(API_URL)

    http =
      Net::HTTP.new(
        uri.host,
        uri.port
      )

    http.use_ssl =
      uri.scheme == "https"

    # Evita que una conexión defectuosa quede esperando
    # indefinidamente.
    http.open_timeout = 10
    http.read_timeout = 20

    request =
      Net::HTTP::Post.new(uri)

    request["Content-Type"] =
      "application/json"

    request["Accept"] =
      "application/json"

    # Si después agregamos autenticación:
    #
    # request["Authorization"] =
    #   "Bearer #{ENV.fetch('TOURFOTOS_API_TOKEN')}"

    request.body =
      payload.to_json

    response =
      http.request(request)

    # ============================================================
    # LOG DE RESPUESTA
    # ============================================================
    Rails.logger.info(
      "[EXTERNAL ROLL] Response: #{response.code} - #{response.body}"
    )

    # También dejamos claramente registrado si TourFotos rechazó
    # el roll.
    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.error(
        "[EXTERNAL ROLL] TourFotos rechazó el roll. HTTP #{response.code}"
      )
    end

    response

  rescue => e
    Rails.logger.error(
      "[EXTERNAL ROLL] ERROR enviando WorkDay #{work_day&.id}: #{e.class} - #{e.message}"
    )

    nil
  end
end