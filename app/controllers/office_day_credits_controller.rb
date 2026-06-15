class OfficeDayCreditsController < ApplicationController
  def index
    @month = selected_month
    @range = @month.beginning_of_month..@month.end_of_month
    @employees = OfficeEmployee.active.order(:name)
  end

  def generate_for_month
    month = selected_month
    range = month.beginning_of_month..month.end_of_month

    OfficeHoliday
      .where(date: range, double_pay: true)
      .find_each do |holiday|
        OfficeDays::HolidayCreditGenerator.new(date: holiday.date).call
      end

    redirect_to office_day_credits_path(month: month.strftime("%Y-%m")),
                notice: "Acumulados generados correctamente."
  end

  private

  def selected_month
    if params[:month].present?
      Date.strptime(params[:month], "%Y-%m")
    else
      Date.today.beginning_of_month
    end
  rescue ArgumentError
    Date.today.beginning_of_month
  end
end
