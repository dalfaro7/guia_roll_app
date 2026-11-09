module GuideAssignmentsHelper
  def weekly_report_tab_path(type)
    guide_assignments_path(report: type, week: @week_start.iso8601,
      guide_id: params[:guide_id].presence, driver_id: params[:driver_id].presence,
      company_id: params[:company_id].presence)
  end

  def weekly_report_tasks(assignment)
    tasks = []
    tasks << "También conduce" if assignment.also_drives?
    tasks << "Guía de bus" if assignment.bus_guide?
    tasks << "Toma y envía fotos" if assignment.photo_task == "take_and_send"
    tasks << "Solo envía fotos" if assignment.photo_task == "send_only"
    tasks
  end

  def weekly_report_lines(day, assignment, include_planned: false)
    item = day[:items_by_assignment][assignment.id]
    return item.details.fetch("lines") if item
    return [] unless assignment.status == "performed" ||
      (include_planned && assignment.status == "planned")

    assignment.compensation_lines.map do |line|
      { "code" => line.code, "amount_cents" => line.amount_cents,
        "discount_percent" => line.discount_percent }
    end
  end
end
