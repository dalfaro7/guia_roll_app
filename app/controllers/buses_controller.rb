class BusesController < ApplicationController
  before_action :set_bus, only: [:show, :edit, :update, :destroy]

  def index
    @query = params[:q].to_s.strip
    @buses = Bus.order(:alias)
    @total_buses = @buses.count
    if @query.present?
      term = "%#{Bus.sanitize_sql_like(@query.downcase)}%"
      @buses = @buses.where(
        'LOWER("buses"."alias") LIKE :term OR LOWER("buses"."company") LIKE :term OR LOWER("buses"."plate") LIKE :term OR LOWER("buses"."phone") LIKE :term',
        term: term
      )
    end
    @buses = @buses.to_a
  end

  def show
  end

  def new
    @bus = Bus.new
  end

  def edit
  end

  def create
    @bus = Bus.new(bus_params)

    if @bus.save
      redirect_to buses_path, notice: "Bus creado correctamente."
    else
      render :new
    end
  end

  def update
    if @bus.update(bus_params)
      redirect_to buses_path, notice: "Bus actualizado correctamente."
    else
      render :edit
    end
  end

  def destroy
    @bus.destroy
    redirect_to buses_path, notice: "Bus eliminado."
  end

  private

  def set_bus
    @bus = Bus.find(params[:id])
  end

  def bus_params
    params.require(:bus).permit(
      :company,
      :capacity,
      :plate,
      :alias,
      :phone
    )
  end
end
