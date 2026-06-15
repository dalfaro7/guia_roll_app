class OfficeOvertimesController < ApplicationController
  before_action :set_overtime, only: [:edit, :update, :destroy]

  def index
    @month = selected_month
    @range = @month.beginning_of_month..@month.end_of_month
    @first_fortnight = @month.beginning_of_month..@month.change(day: 15)
    @second_fortnight = @month.change(day: 16)..@month.end_of_month
    @employees = OfficeEmployee.active.order(:name)
    @overtimes = OfficeOvertime.includes(:office_employee).where(date: @range).order(:date)
  end

  def new
    @overtime = OfficeOvertime.new(date: params[:date])
  end

  def create
    @overtime = OfficeOvertime.new(overtime_params)
    @overtime.minutes = time_to_minutes(params[:office_overtime][:time_amount])

    if @overtime.save
      redirect_to office_overtimes_path(month: @overtime.date.strftime("%Y-%m")),
                  notice: "Hora extra registrada correctamente."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @overtime.assign_attributes(overtime_params)
    @overtime.minutes = time_to_minutes(params[:office_overtime][:time_amount])

    if @overtime.save
      redirect_to office_overtimes_path(month: @overtime.date.strftime("%Y-%m")),
                  notice: "Hora extra actualizada correctamente."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    month = @overtime.date.strftime("%Y-%m")
    @overtime.destroy

    redirect_to office_overtimes_path(month: month),
                notice: "Hora extra eliminada."
  end

  private

  def set_overtime
    @overtime = OfficeOvertime.find(params[:id])
  end

  def overtime_params
    params.require(:office_overtime).permit(
      :office_employee_id,
      :date,
      :reason,
      :approved
    )
  end

  def selected_month
    if params[:month].present?
      Date.strptime(params[:month], "%Y-%m")
    else
      Date.today.beginning_of_month
    end
  rescue ArgumentError
    Date.today.beginning_of_month
  end

  def time_to_minutes(value)
    return 0 if value.blank?

    hours, minutes = value.split(":").map(&:to_i)
    (hours * 60) + minutes
  end
end