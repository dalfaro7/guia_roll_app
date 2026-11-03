class CompensationSettlementsController < ApplicationController
  before_action :require_compensation_view!
  before_action :require_compensation_payment!, only: [:mark_paid]

  def index
    @week_start = Compensation::SettlementService.week_start(
      params[:week_start].present? ? Date.iso8601(params[:week_start]) : Date.current
    )
    @settlements = CompensationSettlement.where(week_start: @week_start)
      .includes(:guide, :driver, :compensation_settlement_items,
        :compensation_adjustments).to_a.sort_by { |s| s.person.name }
  rescue Date::Error
    redirect_to compensation_settlements_path, alert: "Fecha inválida."
  end

  def show
    @settlement = CompensationSettlement.find(params[:id])
    @items = @settlement.compensation_settlement_items
      .includes(compensation_assignment: [:departure, :compensation_lines])
    @adjustments = @settlement.compensation_adjustments
      .includes(:source_assignment)
  end

  def mark_paid
    settlement = CompensationSettlement.find(params[:id])
    settlement.mark_paid!(current_user)
    audit!(action: "mark_compensation_paid", auditable: settlement,
      metadata: { amount_cents: settlement.amount_cents,
        week_start: settlement.week_start, week_end: settlement.week_end })
    redirect_to compensation_settlement_path(settlement), notice: "Pago completo registrado."
  rescue ActiveRecord::RecordInvalid, RuntimeError => e
    redirect_to compensation_settlement_path(params[:id]), alert: e.message
  end
end
