class OfficeDayCreditsController < ApplicationController
  before_action :set_credit, only: [:destroy]

  def index
    @month = selected_month
    @range = @month.beginning_of_month..@month.end_of_month
    @employees = OfficeEmployee.active.order(:name)

    @credits =
      OfficeDayCredit
        .includes(:office_employee)
        .order(used: :asc, date: :asc)
  end

  def new
    @credit = OfficeDayCredit.new(
      date: Date.current,
      source: "legacy",
      used: false
    )
  end

  def create
    @credit = OfficeDayCredit.new(office_day_credit_params)

    quantity = params[:quantity].to_i
    quantity = 1 if quantity < 1

    employee = OfficeEmployee.find(
      office_day_credit_params[:office_employee_id]
    )

    base_date = Date.parse(
      office_day_credit_params[:date]
    )

    OfficeDayCredit.transaction do
      quantity.times do |index|
        OfficeDayCredit.create!(
          office_employee: employee,
          date: base_date + index.days,
          source: "legacy",
          used: false,
          notes: office_day_credit_params[:notes]
        )
      end
    end

    redirect_to office_day_credits_path,
                notice: "#{quantity} acumulado(s) histórico(s) registrados correctamente."

  rescue ActiveRecord::RecordInvalid => error
    @credit.errors.add(:base, error.message)
    render :new, status: :unprocessable_entity

  rescue ArgumentError
    @credit.errors.add(:date, "no es válida")
    render :new, status: :unprocessable_entity
  end

  def destroy
    if @credit.used?
      redirect_to office_day_credits_path,
                  alert: "No se puede eliminar un acumulado que ya fue utilizado."
      return
    end

    @credit.destroy!

    redirect_to office_day_credits_path,
                notice: "Acumulado eliminado correctamente."
  end

  def generate_for_month
    month = selected_month
    range = month.beginning_of_month..month.end_of_month

    OfficeHoliday
      .where(date: range, double_pay: true)
      .find_each do |holiday|

      OfficeDays::HolidayCreditGenerator
        .new(date: holiday.date)
        .call
    end

    redirect_to office_day_credits_path(
      month: month.strftime("%Y-%m")
    ), notice: "Acumulados generados correctamente."
  end

  private

  def set_credit
    @credit = OfficeDayCredit.find(params[:id])
  end

  def office_day_credit_params
    params.require(:office_day_credit).permit(
      :office_employee_id,
      :date,
      :notes
    )
  end

  def selected_month
    if params[:month].present?
      Date.strptime(params[:month], "%Y-%m")
    else
      Date.current.beginning_of_month
    end
  rescue ArgumentError
    Date.current.beginning_of_month
  end
end
