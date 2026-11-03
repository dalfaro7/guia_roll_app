class CompensationDiscountRulesController < ApplicationController
  before_action :require_admin!
  before_action :require_rates_page_key!

  def create
    effective_at = Time.find_zone!("America/Costa_Rica").parse(rule_params[:effective_at].to_s)
    raise "La nueva vigencia debe ser futura" unless effective_at && effective_at > Time.current

    rule = CompensationDiscountRule.create!(
      code: rule_params[:code], percent: Integer(rule_params[:percent]),
      effective_at: effective_at, created_by: current_user
    )
    audit!(action: "create_compensation_discount_rule", auditable: rule,
      metadata: { code: rule.code, percent: rule.percent,
        effective_at: rule.effective_at })
    redirect_to compensation_rates_path, notice: "Nuevo descuento registrado."
  rescue ActiveRecord::RecordInvalid, ArgumentError, RuntimeError => e
    redirect_to compensation_rates_path, alert: e.message
  end

  private

  def rule_params
    params.require(:compensation_discount_rule).permit(:code, :percent, :effective_at)
  end
end
