class OfficeDayCreditsController < ApplicationController
  before_action :require_admin!,
                only: [:new, :create, :destroy, :generate_for_month]
                
  before_action :set_credit, only: [:destroy]

  def index
    @month = selected_month
    @range = @month.beginning_of_month..@month.end_of_month
    @employees = OfficeEmployee.active.order(:name)

    @credits =
      OfficeDayCredit
        .includes(:office_employee)
        .order(used: :asc, date: :asc, id: :asc)
  end

  def new
    @credit = OfficeDayCredit.new(
      date: Date.current,
      source: "legacy",
      used: false
    )
  end

  def create
    @credit = OfficeDayCredit.new(
      office_day_credit_params
    )

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
          date: available_legacy_date(
            employee: employee,
            base_date: base_date,
            offset: index
          ),
          source: "legacy",
          used: false,
          notes: office_day_credit_params[:notes]
        )
      end
    end

    redirect_to office_day_credits_path,
                notice: "#{quantity} acumulado(s) histórico(s) registrados correctamente."

  rescue ActiveRecord::RecordInvalid => error
    @credit.errors.add(
      :base,
      error.record.errors.full_messages.to_sentence
    )

    render :new,
           status: :unprocessable_entity

  rescue ActiveRecord::RecordNotFound
    @credit.errors.add(
      :office_employee,
      "no fue encontrado"
    )

    render :new,
           status: :unprocessable_entity

  rescue ArgumentError
    @credit.errors.add(
      :date,
      "no es válida"
    )

    render :new,
           status: :unprocessable_entity
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

    OfficeDays::MonthHolidayCreditSyncer
      .new(month: month)
      .call

    redirect_to office_day_credits_path(
      month: month.strftime("%Y-%m")
    ), notice: "Acumulados de feriados sincronizados correctamente."
  end

  private

  def set_credit
    @credit = OfficeDayCredit.find(
      params[:id]
    )
  end

  def available_legacy_date(employee:, base_date:, offset:)
    candidate_date = base_date + offset.days

    while OfficeDayCredit.exists?(
      office_employee: employee,
      date: candidate_date,
      source: "legacy"
    )
      candidate_date += 1.day
    end

    candidate_date
  end

  def office_day_credit_params
    params.require(
      :office_day_credit
    ).permit(
      :office_employee_id,
      :date,
      :notes
    )
  end

  def selected_month
    if params[:month].present?
      Date.strptime(
        params[:month],
        "%Y-%m"
      )
    else
      Date.current.beginning_of_month
    end
  rescue ArgumentError
    Date.current.beginning_of_month
  end
end