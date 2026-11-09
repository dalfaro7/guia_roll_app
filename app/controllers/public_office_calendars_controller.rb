class PublicOfficeCalendarsController < ApplicationController
  skip_before_action :authenticate_user!
  layout "public_office_calendar"

  def show
    response.headers["Cache-Control"] = "no-store"
    response.headers["X-Robots-Tag"] = "noindex, nofollow, noarchive"
    response.headers["Referrer-Policy"] = "no-referrer"
    data = OfficeDays::PublicCalendarLink.read(params[:token].to_s)
    return invalid_link unless data.is_a?(Hash) && data["month"].to_s.match?(/\A\d{4}-\d{2}\z/)

    @month = Date.strptime(data.fetch("month"), "%Y-%m")
    @employee = OfficeEmployee.find_by(id: data["employee_id"])
    return invalid_link unless @employee

    @days = @employee.office_employee_days.day_off
      .where(date: @month..@month.end_of_month).order(:date).pluck(:date)
    @weeks = (@month.beginning_of_week(:monday)..@month.end_of_month.end_of_week(:monday)).each_slice(7).to_a
  rescue ArgumentError
    invalid_link
  end

  private

  def invalid_link
    render plain: "Este enlace no es válido o ya no está disponible.", status: :not_found
  end
end
