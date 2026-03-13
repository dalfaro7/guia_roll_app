class BusesController < ApplicationController
  before_action :set_bus, only: [:show, :edit, :update, :destroy]

  def index
    @buses = Bus.order(:alias)
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
      redirect_to buses_path, notice: "Bus created successfully."
    else
      render :new
    end
  end

  def update
    if @bus.update(bus_params)
      redirect_to buses_path, notice: "Bus updated successfully."
    else
      render :edit
    end
  end

  def destroy
    @bus.destroy
    redirect_to buses_path, notice: "Bus deleted."
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
