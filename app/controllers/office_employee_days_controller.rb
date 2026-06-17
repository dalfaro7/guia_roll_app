class OfficeEmployeeDaysController < ApplicationController
  before_action :set_office_employee_day, only: [:edit, :update, :destroy]

  def index
  @month = selected_month

  @month_range =
    @month.beginning_of_month..@month.end_of_month

  @calendar_range =
    @month.beginning_of_month.beginning_of_week(:monday)..
    @month.end_of_month.end_of_week(:monday)

  @weeks = []
  current = @calendar_range.begin

  while current <= @calendar_range.end
    @weeks << (current..current.end_of_week(:monday))
    current += 1.week
  end

  @employees = OfficeEmployee.active.order(:name)

  @employee_days =
    OfficeEmployeeDay
      .includes(:office_employee)
      .where(date: @calendar_range)
      .index_by { |day| [day.office_employee_id, day.date] }

  @holidays =
    OfficeHoliday
      .where(date: @calendar_range)
      .index_by(&:date)
end


  def new
    @office_employee_day = OfficeEmployeeDay.new(
      date: params[:date],
      office_employee_id: params[:office_employee_id]
    )
  end

  def create
    @office_employee_day = OfficeEmployeeDay.new(office_employee_day_params)

    if @office_employee_day.day_off?
      @office_employee_day.day_off_source = "manual"
    end

    if @office_employee_day.save
      generate_holiday_credit_for(@office_employee_day)

      redirect_to office_employee_days_path(
        month: @office_employee_day.date.strftime("%Y-%m")
      ), notice: "Registro creado correctamente."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @office_employee_day.update(office_employee_day_params)
      if @office_employee_day.day_off? &&
         @office_employee_day.day_off_source.blank?

        @office_employee_day.update!(
          day_off_source: "manual"
        )
      end

      generate_holiday_credit_for(@office_employee_day)

      redirect_to office_employee_days_path(
        month: @office_employee_day.date.strftime("%Y-%m")
      ), notice: "Registro actualizado correctamente."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    month = @office_employee_day.date.strftime("%Y-%m")

    @office_employee_day.destroy

    redirect_to office_employee_days_path(month: month),
                notice: "Registro eliminado correctamente."
  end

  def generate_month
  month = selected_month
  range = month.beginning_of_month..month.end_of_month

  if OfficeHoliday.where(date: range, double_pay: true).none?
    redirect_to office_holidays_path,
                alert: "Antes de generar el calendario, registre los feriados de pago doble del mes."
    return
  end

  OfficeDays::DayOffGenerator.new(month: month).call
  OfficeDays::MonthHolidayCreditSyncer.new(month: month).call

  redirect_to office_employee_days_path(month: month.strftime("%Y-%m")),
              notice: "Calendario generado y acumulados sincronizados correctamente."
end

  private

  def set_office_employee_day
    @office_employee_day =
      OfficeEmployeeDay.find(params[:id])
  end

  def generate_holiday_credit_for(employee_day)
    return unless employee_day.holiday_worked?

    OfficeDays::HolidayCreditGenerator
      .new(date: employee_day.date)
      .call
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

  def office_employee_day_params
    params.require(:office_employee_day).permit(
      :office_employee_id,
      :date,
      :status,
      :holiday_paid,
      :notes
    )
  end
end