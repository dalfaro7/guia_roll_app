class BusesController < ApplicationController
  before_action :set_bus, only: [:show, :edit, :update, :destroy]
  before_action :load_companies, only: [:new, :edit, :create, :update]

  def index
    @query = params[:q].to_s.strip
    @buses = Bus.includes(:transport_company).order(:alias)
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
    four_by_four = params[:vehicle_kind] == "four_by_four"
    @bus = Bus.new(vehicle_kind: four_by_four ? "four_by_four" : "bus")
    if four_by_four
      @bus.transport_company = TransportCompany.find_by(name: "ARC", internal_fleet: true) ||
        TransportCompany.where(internal_fleet: true).order(:name).first
    end
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
    if bus_params[:transport_company_id].present? &&
        @bus.transport_company_id != bus_params[:transport_company_id].to_i
      Bus.transaction do
        result = BusCompanyReassignment.call(bus: @bus, attributes: bus_params)
        audit!(action: "reassign_bus_company", auditable: @bus,
          metadata: result)
      end
      redirect_to buses_path, notice: "Empresa actualizada. Los viajes anteriores conservan sus datos; los futuros usan la nueva tarifa."
    elsif @bus.update(bus_params)
      redirect_to buses_path, notice: "Bus actualizado correctamente."
    else
      render :edit
    end
  rescue BusCompanyReassignment::Conflict => e
    @bus.reload
    flash.now[:alert] = e.message
    render :edit, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    @bus.errors.add(:base, e.record.errors.full_messages.to_sentence) unless e.record == @bus
    render :edit, status: :unprocessable_entity
  end

  def destroy
    if @bus.destroy
      redirect_to buses_path, notice: "Vehículo eliminado."
    else
      redirect_to bus_path(@bus), alert: @bus.errors.full_messages.to_sentence
    end
  end

  private

  def set_bus
    @bus = Bus.find(params[:id])
  end

  def load_companies
    @companies = TransportCompany.order(:name)
  end

  def bus_params
    params.require(:bus).permit(
      :transport_company_id,
      :capacity,
      :vehicle_kind,
      :plate,
      :alias,
      :phone
    )
  end
end
