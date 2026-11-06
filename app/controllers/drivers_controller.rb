class DriversController < ApplicationController
  before_action :require_compensation_operator!

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
    before = driver.attributes.slice("name", "active", "phone", "transport_company_id", "payment_mode")
    driver.update!(driver_params)
    audit!(action: "update_driver", auditable: driver,
      metadata: { before: before, after: driver.attributes.slice(*before.keys) })
    redirect_to drivers_path, notice: "Chofer actualizado."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to drivers_path, alert: e.record.errors.full_messages.to_sentence
  end

  def destroy
    driver = Driver.find(params[:id])
    if driver.bus_assignments.exists? || driver.compensation_assignments.exists? ||
        driver.compensation_settlements.exists?
      redirect_to drivers_path,
        alert: "No se puede eliminar a #{driver.name}: tiene viajes o pagos registrados. Puedes desactivarlo."
      return
    end

    if driver.destroy
      audit!(action: "destroy_driver", auditable: driver,
        metadata: { name: driver.name, transport_company_id: driver.transport_company_id })
      redirect_to drivers_path, notice: "Chofer eliminado."
    else
      redirect_to drivers_path,
        alert: "No se pudo eliminar a #{driver.name}. Revisa sus asignaciones y pagos."
    end
  end

  private

  def driver_params
    params.require(:driver).permit(:name, :active, :phone, :transport_company_id, :payment_mode)
  end
end
