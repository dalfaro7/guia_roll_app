class TransportRatesController < ApplicationController
  before_action :require_compensation_view!, only: :index
  before_action :require_compensation_operator!, only: :update

  def index
    @rates = TransportRate.order(:location, :size_category).index_by do |rate|
      [rate.location, rate.size_category]
    end
  end

  def update
    rate = TransportRate.find(params[:id])
    before_cents = rate.amount_cents
    TransportRate.transaction do
      rate.update!(amount_usd: params.require(:transport_rate).fetch(:amount_usd, nil))
      audit!(action: "update_transport_rate", auditable: rate,
        metadata: { location: rate.location, size_category: rate.size_category,
          before_cents: before_cents, after_cents: rate.amount_cents })
    end
    redirect_to transport_rates_path, notice: "Tarifa de transporte actualizada."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to transport_rates_path, alert: e.record.errors.full_messages.to_sentence
  end
end
