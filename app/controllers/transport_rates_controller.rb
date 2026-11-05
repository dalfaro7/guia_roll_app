class TransportRatesController < ApplicationController
  before_action :require_compensation_view!, only: :index
  before_action :require_compensation_operator!, only: :bulk_update
  before_action :load_companies, only: %i[index bulk_update]

  def index
    @editing = @can_edit && @company.present? && params[:edit] == "1"
  end

  def bulk_update
    raise ActionController::ParameterMissing, :transport_company_id unless @company

    @editing = true
    @submitted_rates = params.require(:rates).permit!.to_h
    expected_ids = @company.transport_rates.filter_map do |rate|
      rate.id.to_s if TransportRate::LOCATIONS.include?(rate.location) &&
        TransportRate::RATE_TYPES.include?([rate.vehicle_kind, rate.size_category]) &&
        @company.offers_vehicle_category?(vehicle_kind: rate.vehicle_kind,
          size_category: rate.size_category)
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
    redirect_to transport_rates_path(transport_company_id: @company.id),
      notice: changed.zero? ? "No hubo cambios en las tarifas de #{@company.name}." :
        "#{changed} #{changed == 1 ? 'tarifa actualizada' : 'tarifas actualizadas'} de #{@company.name}."
  rescue ActionController::ParameterMissing, ArgumentError, ActiveRecord::RecordInvalid => e
    message = e.is_a?(ActiveRecord::RecordInvalid) ? e.record.errors.full_messages.to_sentence : e.message
    flash.now[:alert] = message
    render :index, status: :unprocessable_entity
  end

  private

  def load_companies
    @all_companies = TransportCompany.includes(:transport_rates).order(:name).to_a
    if params[:transport_company_id].present?
      @company = @all_companies.find { |company| company.id.to_s == params[:transport_company_id].to_s }
      raise ActiveRecord::RecordNotFound, "Empresa de transporte no encontrada" unless @company
    end
    @companies = @company ? [@company] : @all_companies
    @can_edit = current_user.admin? || current_user.operador?
    @editing = false
  end
end
