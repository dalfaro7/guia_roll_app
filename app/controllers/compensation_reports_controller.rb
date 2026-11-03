class CompensationReportsController < ApplicationController
  before_action :require_compensation_view!

  def index
    month = params[:month].present? ? Date.iso8601("#{params[:month]}-01") : Date.current.beginning_of_month
    @month = month.beginning_of_month
    @first_range = @month..(@month + 14.days)
    @second_range = (@month + 15.days)..@month.end_of_month
    @assignments = CompensationAssignment.joins(departure: :work_day)
      .where(work_days: { date: @month..@month.end_of_month })
      .where(status: "performed")
      .includes(:guide, :driver, :compensation_lines, departure: :work_day)
  rescue Date::Error
    redirect_to compensation_reports_path, alert: "Mes inválido."
  end
end
