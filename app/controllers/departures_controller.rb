class DeparturesController < ApplicationController
  before_action :require_compensation_operator!
  before_action :set_work_day
  before_action :require_open_window

  def create
    departure = @work_day.departures.new(departure_params.except(:starts_at_time))
    departure.starts_at = scheduled_start
    departure.save!
    audit!(action: "create_departure", auditable: departure, work_day: @work_day)
    redirect_to work_day_compensation_path(@work_day), notice: "Salida creada."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to work_day_compensation_path(@work_day), alert: e.record.errors.full_messages.to_sentence
  end

  def update
    departure = @work_day.departures.find(params[:id])
    if departure.started? && departure_params[:starts_at_time].present? &&
        scheduled_start != departure.starts_at && !current_user.admin?
      raise "Solo un administrador puede cambiar la hora de una salida iniciada"
    end

    before = departure.attributes.slice("label", "location", "starts_at", "status")
    Compensation::Current.set(actor: current_user, reason: params[:correction_reason]) do
      Departure.transaction do
        attrs = departure_params.except(:starts_at_time)
        attrs[:starts_at] = scheduled_start if departure_params[:starts_at_time].present?
        departure.update!(attrs)
        if departure.status == "canceled"
          departure.compensation_assignments.where(status: "planned")
            .update_all(status: "canceled", updated_at: Time.current)
        end
        Compensation::RepriceDay.call(@work_day)
        audit!(action: "update_departure", auditable: departure, work_day: @work_day,
          metadata: { before: before,
            after: departure.attributes.slice(*before.keys), reason: params[:correction_reason] })
      end
    end
    redirect_to work_day_compensation_path(@work_day), notice: "Salida actualizada."
  rescue ActiveRecord::RecordInvalid, RuntimeError => e
    redirect_to work_day_compensation_path(@work_day), alert: e.message
  end

  private

  def set_work_day
    @work_day = WorkDay.find(params[:work_day_id])
  end

  def departure_params
    params.require(:departure).permit(:label, :location, :starts_at_time, :status)
  end

  def scheduled_start
    hour = departure_params[:starts_at_time].to_s
    raise "Indique la hora de inicio" unless hour.match?(/\A\d{2}:\d{2}\z/)

    Time.find_zone!("America/Costa_Rica").parse("#{@work_day.date} #{hour}")
  end

  def require_open_window
    unless Compensation::EditWindow.applicable?(@work_day)
      redirect_to work_day_compensation_path(@work_day),
        alert: "La valoración económica aún no aplica a esta fecha."
      return
    end
    return if Compensation::EditWindow.allowed?(user: current_user, work_day: @work_day) &&
      (!requires_reason? || params[:correction_reason].present?)

    redirect_to work_day_compensation_path(@work_day),
      alert: requires_reason? ? "Indique el motivo de la corrección." :
        "Esta programación ya cerró. Solo un administrador puede corregirla."
  end

  def requires_reason?
    current_user.admin? && Compensation::EditWindow.closed?(@work_day)
  end
end
