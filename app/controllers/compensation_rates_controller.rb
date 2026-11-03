class CompensationRatesController < ApplicationController
  before_action :require_admin!
  before_action :require_rates_page_key!, only: [:index, :create]

  def unlock
    redirect_to compensation_rates_path if session[:compensation_rates_unlocked_user_id] == current_user.id
  end

  def verify_key
    expected = ENV["COMPENSATION_RATES_PAGE_KEY"].presence || "admin"
    if ActiveSupport::SecurityUtils.secure_compare(
      Digest::SHA256.hexdigest(params[:password].to_s),
      Digest::SHA256.hexdigest(expected)
    )
      session[:compensation_rates_unlocked_user_id] = current_user.id
      redirect_to compensation_rates_path
    else
      redirect_to unlock_compensation_rates_path, alert: "Clave incorrecta."
    end
  end

  def index
    @rates = CompensationRate.order(:code, effective_at: :desc)
    @current_rates = CompensationRate::CODES.index_with do |code|
      CompensationRate.for(code, at: Time.current)
    end
    @discount_rules = CompensationDiscountRule.where(code: CompensationDiscountRule::CODES)
      .order(:code, effective_at: :desc)
    @current_discount_rules = CompensationDiscountRule::CODES.index_with do |code|
      CompensationDiscountRule.for(code, at: Time.current)
    end
  end

  def create
    effective_at = Time.find_zone!("America/Costa_Rica").parse(rate_params[:effective_at].to_s)
    raise "La nueva vigencia debe ser futura" unless effective_at && effective_at > Time.current

    cents = (BigDecimal(rate_params[:amount_usd].to_s) * 100).round(0).to_i
    rate = CompensationRate.create!(
      code: rate_params[:code], amount_cents: cents,
      effective_at: effective_at, created_by: current_user
    )
    audit!(action: "create_compensation_rate", auditable: rate,
      metadata: { code: rate.code, amount_cents: rate.amount_cents,
        effective_at: rate.effective_at })
    redirect_to compensation_rates_path, notice: "Nueva tarifa registrada."
  rescue ActiveRecord::RecordInvalid, ArgumentError, RuntimeError => e
    redirect_to compensation_rates_path, alert: e.message
  end

  private

  def rate_params
    params.require(:compensation_rate).permit(:code, :amount_usd, :effective_at)
  end
end
