module ApplicationHelper
  def roll_skill_label(value)
    { "ClassIII" => "Clase III", "ClassIV" => "Clase IV", "Computer" => "Computadora" }.fetch(value.to_s, roll_role_label(value))
  end

  def roll_status_label(value)
    { "worked" => "Trabajó", "standby" => "En espera", "day_off" => "Día libre",
      "vacation" => "Vacaciones", "penalized" => "Penalizado", "assigned_task" => "Tarea asignada",
      "draft" => "Borrador", "generated" => "Generado", "published" => "Publicado" }.fetch(value.to_s, value.to_s)
  end

  def roll_role_label(value)
    { "River Guide" => "Guía de río", "Safety Kayaker" => "Kayakista de seguridad",
      "Photographer" => "Fotógrafo", "Head Guide" => "Guía líder", "Driver" => "Chofer",
      "Bus Guide & Towels" => "Guía de bus y toallas", "Bus Guide" => "Guía de bus",
      "Bus Guide, towels & SendPhotos" => "Guía de bus, toallas y envío de fotos",
      "SendPhotos" => "Envío de fotos" }.fetch(value.to_s, value.presence || "—")
  end

  def office_employee_day_entry(day, &block)
    content = capture(&block)
    return content unless current_user&.admin?

    link_to(
      content,
      edit_office_employee_day_path(day),
      class: "text-decoration-none"
    )
  end
end
