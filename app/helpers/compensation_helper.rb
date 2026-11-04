module CompensationHelper
  DISCOUNT_LABELS = {
    "second_sara" => "Segunda salida en Sarapiquí"
  }.freeze

  def compensation_discount_label(code)
    DISCOUNT_LABELS.fetch(code, code)
  end
  LABELS = {
    "river_guide" => "Guía de río",
    "tl_balsa" => "TL Balsa",
    "tl_sara" => "TL Sarapiquí",
    "hg_balsa" => "HG Balsa",
    "hg_sara" => "HG Sarapiquí",
    "safety_kayak" => "Kayak de seguridad",
    "photographer" => "Fotógrafo",
    "driver_la_fortuna" => "Chofer Round Trip La Fortuna",
    "driver_bodega" => "Chofer Round Trip Bodega",
    "driver_hg" => "Chofer HG",
    "guide_apprentice" => "Guía aprendiz",
    "guide_regular" => "Guía regular",
    "guide_invoice" => "Guía con factura",
    "bonus_guide_drives" => "Guía que también conduce",
    "bonus_photo_take_and_send" => "Toma y envía fotos",
    "bonus_photo_send_only" => "Solo envía fotos",
    "bonus_photographer" => "Fotógrafo toma fotos",
    "bonus_photographer_priority_zero" => "Fotógrafo prioridad 0: toma y envía fotos",
    "bonus_bus_guide" => "Guía de bus"
  }.freeze

  def compensation_label(code)
    LABELS.fetch(code.to_s, code.to_s.humanize)
  end

  def compensation_guide_roles_for(departure)
    suffix = Departure.leader_rate_suffix_for(departure.location)
    CompensationAssignment::GUIDE_ROLES.reject do |code|
      code.start_with?("tl_", "hg_") && (suffix.nil? || !code.end_with?("_#{suffix}"))
    end
  end

  def usd(cents)
    number_to_currency(cents.to_i / 100.0, unit: "$", precision: 2)
  end

  def compensation_correction_required?(work_day)
    return false unless current_user&.admin?
    return false unless Compensation::EditWindow.applicable?(work_day)

    Compensation::EditWindow.closed?(work_day)
  end
end
