class TransportRatesController < ApplicationController
  before_action :require_compensation_view!, only: :index
  before_action :require_compensation_operator!, only: :bulk_update

  def index
    @companies = TransportCompany.includes(:transport_rates).order(:name).to_a
    @can_edit = current_user.admin? || current_user.operador?
    @editing = @can_edit && params[:edit] == "1"
  end

  def bulk_update
    @companies = TransportCompany.includes(:transport_rates).order(:name).to_a
    @can_edit = true
    @editing = true
    @submitted_rates = params.require(:rates).permit!.to_h
    expected_ids = @companies.flat_map do |company|
      company.transport_rates.filter_map do |rate|
        rate.id.to_s if TransportRate::LOCATIONS.include?(rate.location) &&
          TransportRate::RATE_TYPES.include?([rate.vehicle_kind, rate.size_category])
      end
    end
    unless @submitted_rates.keys.sort == expected_ids.sort
      raise ArgumentError, "La lista de tarifas cambió. Recargue la página e inténtelo de nuevo."
    end

    changed = 0
    TransportRate.transaction do
      TransportRate.where(id: expected_ids).order(:id).lock.each do |rate|
        before_cents = rate.amount_cents
        rate.amount_usd = @submitted_rates.fetch(rate.id.to_s)
        next unless rate.changed?

        rate.save!
        changed += 1
        audit!(action: "update_transport_rate", auditable: rate,
          metadata: { transport_company_id: rate.transport_company_id,
            location: rate.location, vehicle_kind: rate.vehicle_kind,
            size_category: rate.size_category, before_cents: before_cents,
            after_cents: rate.amount_cents })
      end
    end
    redirect_to transport_rates_path,
      notice: changed.zero? ? "No hubo cambios en las tarifas." :
        "#{changed} #{changed == 1 ? 'tarifa actualizada' : 'tarifas actualizadas'} correctamente."
  rescue ActionController::ParameterMissing, ArgumentError, ActiveRecord::RecordInvalid => e
    message = e.is_a?(ActiveRecord::RecordInvalid) ? e.record.errors.full_messages.to_sentence : e.message
    flash.now[:alert] = message
    render :index, status: :unprocessable_entity
  end
end
