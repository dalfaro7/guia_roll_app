class OfficeHolidaysController < ApplicationController
  before_action :set_holiday, only: [:edit, :update, :destroy]

  def index
    @holidays = OfficeHoliday.order(:date)
  end

  def new
    @holiday = OfficeHoliday.new
  end

  def create
    @holiday = OfficeHoliday.new(holiday_params)

    if @holiday.save
      redirect_to office_holidays_path,
                  notice: "Feriado creado correctamente."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @holiday.update(holiday_params)
      redirect_to office_holidays_path,
                  notice: "Feriado actualizado correctamente."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @holiday.destroy

    redirect_to office_holidays_path,
                notice: "Feriado eliminado."
  end

  private

  def set_holiday
    @holiday = OfficeHoliday.find(params[:id])
  end

  def holiday_params
    params.require(:office_holiday).permit(
      :date,
      :name,
      :double_pay
    )
  end
end
