class DriversController < ApplicationController
  before_action :require_admin!

  def index
    @drivers = Driver.includes(:transport_company).order(:name)
    @companies = TransportCompany.order(:name)
  end

  def create
    driver = Driver.create!(driver_params)
    audit!(action: "create_driver", auditable: driver)
    redirect_to drivers_path, notice: "Chofer registrado."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to drivers_path, alert: e.record.errors.full_messages.to_sentence
  end

  def update
    driver = Driver.find(params[:id])
    before = driver.attributes.slice("name", "active", "phone", "transport_company_id")
    driver.update!(driver_params)
    audit!(action: "update_driver", auditable: driver,
      metadata: { before: before, after: driver.attributes.slice(*before.keys) })
    redirect_to drivers_path, notice: "Chofer actualizado."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to drivers_path, alert: e.record.errors.full_messages.to_sentence
  end

  private

  def driver_params
    params.require(:driver).permit(:name, :active, :phone, :transport_company_id)
  end
end
