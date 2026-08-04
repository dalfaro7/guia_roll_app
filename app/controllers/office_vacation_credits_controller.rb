class OfficeVacationCreditsController < ApplicationController
  before_action :require_admin!,
              only: [:new, :create, :destroy]
  before_action :set_credit, only: [:destroy]

  def index
    @employees = OfficeEmployee.active.order(:name)

    @credits =
      OfficeVacationCredit
        .includes(:office_employee)
        .order(used: :asc, date: :asc, id: :asc)
  end

  def new
    @credit = OfficeVacationCredit.new(
      date: Date.current,
      source: "legacy",
      used: false
    )
  end

  def create
    @credit = OfficeVacationCredit.new(
      office_vacation_credit_params
    )

    quantity = params[:quantity].to_i
    quantity = 1 if quantity < 1

    employee = OfficeEmployee.find(
      office_vacation_credit_params[:office_employee_id]
    )

    base_date = Date.parse(
      office_vacation_credit_params[:date]
    )

    OfficeVacationCredit.transaction do
      quantity.times do |index|
        OfficeVacationCredit.create!(
          office_employee: employee,
          date: available_legacy_date(
            employee: employee,
            base_date: base_date,
            offset: index
          ),
          source: "legacy",
          used: false,
          notes: office_vacation_credit_params[:notes]
        )
      end
    end

    redirect_to office_vacation_credits_path,
                notice: "#{quantity} día(s) de vacaciones registrados correctamente."

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
      redirect_to office_vacation_credits_path,
                  alert: "No se puede eliminar un día de vacaciones que ya fue utilizado."
      return
    end

    @credit.destroy!

    redirect_to office_vacation_credits_path,
                notice: "Día de vacaciones eliminado correctamente."
  end

  private

  def set_credit
    @credit = OfficeVacationCredit.find(
      params[:id]
    )
  end

  def available_legacy_date(employee:, base_date:, offset:)
    candidate_date = base_date + offset.days

    while OfficeVacationCredit.exists?(
      office_employee: employee,
      date: candidate_date,
      source: "legacy"
    )
      candidate_date += 1.day
    end

    candidate_date
  end

  def office_vacation_credit_params
    params.require(
      :office_vacation_credit
    ).permit(
      :office_employee_id,
      :date,
      :notes
    )
  end
end
