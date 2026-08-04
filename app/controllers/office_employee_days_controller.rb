class OfficeEmployeeDaysController < ApplicationController
  before_action :set_office_employee_day,
                only: [:edit, :update, :destroy]

  before_action :require_admin!,
                only: [
                  :new,
                  :create,
                  :edit,
                  :update,
                  :destroy,
                  :generate_month
                ]

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

    @employees = OfficeEmployee.active.to_a

    @employee_days =
      OfficeEmployeeDay
        .includes(
          :office_employee,
          :office_day_credit,
          :office_vacation_credit
        )
        .where(date: @calendar_range)
        .index_by do |day|
          [day.office_employee_id, day.date]
        end

    @holidays =
      OfficeHoliday
        .where(date: @calendar_range)
        .index_by(&:date)
  end


  def create
    use_day_credit =
      params.dig(
        :office_employee_day,
        :use_day_credit
      )

    attributes =
      office_employee_day_params.except(
        :use_day_credit
      )

    @office_employee_day =
      OfficeEmployeeDay.new(attributes)

    assign_day_off_source(
      @office_employee_day,
      use_day_credit
    )

    OfficeEmployeeDay.transaction do
      @office_employee_day.save!

      synchronize_assigned_credits(
        employee_day: @office_employee_day,
        use_day_credit: use_day_credit
      )

      sync_holiday_credit(
        @office_employee_day
      )
    end

    redirect_to office_employee_days_path(
      month: @office_employee_day.date.strftime("%Y-%m")
    ), notice: "Registro creado correctamente."

  rescue OfficeDays::CreditAssignmentService::NoAvailableCreditError => error
    @office_employee_day.errors.add(
      :base,
      error.message
    )

    render :new, status: :unprocessable_entity

  rescue ActiveRecord::RecordInvalid => error
    @office_employee_day.errors.add(
      :base,
      error.message
    )

    render :new, status: :unprocessable_entity
  end

  def new
  employee_id =
    params[:office_employee_id].presence ||
    OfficeEmployee.active.order(:name).pick(:id)

  @office_employee_day = OfficeEmployeeDay.new(
    date: params[:date].presence || Date.current,
    office_employee_id: employee_id
  )
end

def edit
  if params[:office_employee_id].present?
    @office_employee_day.office_employee_id =
      params[:office_employee_id]
  end

  if params[:date].present?
    @office_employee_day.date = params[:date]
  end
end

  def update
    use_day_credit =
      params.dig(
        :office_employee_day,
        :use_day_credit
      )

    attributes =
      office_employee_day_params.except(
        :use_day_credit
      )

    OfficeEmployeeDay.transaction do
      @office_employee_day.assign_attributes(
        attributes
      )

      assign_day_off_source(
        @office_employee_day,
        use_day_credit
      )

      @office_employee_day.save!

      synchronize_assigned_credits(
        employee_day: @office_employee_day,
        use_day_credit: use_day_credit
      )

      sync_holiday_credit(
        @office_employee_day
      )
    end

    redirect_to office_employee_days_path(
      month: @office_employee_day.date.strftime("%Y-%m")
    ), notice: "Registro actualizado correctamente."

  rescue OfficeDays::CreditAssignmentService::NoAvailableCreditError => error
    @office_employee_day.errors.add(
      :base,
      error.message
    )

    render :edit, status: :unprocessable_entity

  rescue ActiveRecord::RecordInvalid => error
    @office_employee_day.errors.add(
      :base,
      error.message
    )

    render :edit, status: :unprocessable_entity
  end

  def destroy
    month =
      @office_employee_day.date.strftime("%Y-%m")

    OfficeEmployeeDay.transaction do
      release_all_assigned_credits(
        @office_employee_day
      )

      remove_holiday_credit(
        @office_employee_day
      )

      @office_employee_day.destroy!
    end

    redirect_to office_employee_days_path(
      month: month
    ), notice: "Registro eliminado correctamente."
  end

  def generate_month
    month = selected_month

    range =
      month.beginning_of_month..
      month.end_of_month

    holiday_answer =
      params[:has_double_pay_holidays]

    unless %w[yes no].include?(holiday_answer)
      redirect_to office_employee_days_path(
        month: month.strftime("%Y-%m")
      ), alert: "Indique si el mes tiene feriados de pago doble."

      return
    end

    holidays =
      OfficeHoliday.where(
        date: range,
        double_pay: true
      )

    if holiday_answer == "yes" && holidays.none?
      redirect_to new_office_holiday_path(
        month: month.strftime("%Y-%m")
      ), alert: "Registre los feriados de pago doble antes de generar el calendario."

      return
    end

    if holiday_answer == "no" && holidays.exists?
      redirect_to office_employee_days_path(
        month: month.strftime("%Y-%m")
      ), alert: "Este mes ya tiene feriados de pago doble registrados. Seleccione «Sí» o revise la lista de feriados."

      return
    end

    OfficeDays::DayOffGenerator
      .new(month: month)
      .call

    if holiday_answer == "yes"
      OfficeDays::MonthHolidayCreditSyncer
        .new(month: month)
        .call
    end

    redirect_to office_employee_days_path(
      month: month.strftime("%Y-%m")
    ), notice: "Calendario generado correctamente."
  end

  private

  def set_office_employee_day
    @office_employee_day =
      OfficeEmployeeDay.find(params[:id])
  end

  def synchronize_assigned_credits(employee_day:, use_day_credit:)
    OfficeDays::CreditAssignmentService.new(
      employee_day: employee_day,
      credit_type: :day,
      use_credit: use_day_credit
    ).call

    OfficeDays::CreditAssignmentService.new(
      employee_day: employee_day,
      credit_type: :vacation,
      use_credit: employee_day.vacation?
    ).call
  end

  def release_all_assigned_credits(employee_day)
    OfficeDays::CreditAssignmentService.new(
      employee_day: employee_day,
      credit_type: :day,
      use_credit: false
    ).call

    OfficeDays::CreditAssignmentService.new(
      employee_day: employee_day,
      credit_type: :vacation,
      use_credit: false
    ).call
  end

  def assign_day_off_source(employee_day, use_day_credit)
    unless employee_day.day_off?
      employee_day.day_off_source = nil
      return
    end

    employee_day.day_off_source =
      if use_credit_selected?(use_day_credit)
        "credit"
      elsif employee_day.day_off_source == "automatic"
        "automatic"
      else
        "manual"
      end
  end

  def sync_holiday_credit(employee_day)
    OfficeDays::HolidayCreditSyncer
      .new(employee_day: employee_day)
      .call
  end

  def remove_holiday_credit(employee_day)
    OfficeDayCredit
      .where(
        office_employee: employee_day.office_employee,
        date: employee_day.date,
        source: "holiday_worked"
      )
      .destroy_all
  end

  def use_credit_selected?(value)
    ActiveModel::Type::Boolean
      .new
      .cast(value)
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

  def office_employee_day_params
    params.require(
      :office_employee_day
    ).permit(
      :office_employee_id,
      :date,
      :status,
      :holiday_paid,
      :notes,
      :use_day_credit
    )
  end
end