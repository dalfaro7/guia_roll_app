class GuidesController < ApplicationController
  # before_action :require_admin!

  before_action :set_guide, only: [
    :edit,
    :update,
    :toggle_active
  ]

  def index
    @guides = Guide.includes(:skills)

    if params[:name].present?
      @guides =
        @guides.where(
          "LOWER(name) LIKE ?",
          "%#{params[:name].downcase}%"
        )
    end

    if params[:priority].present?
      @guides =
        @guides.where(
          priority: params[:priority]
        )
    end

    if params[:skill_id].present?
      @guides =
        @guides
          .joins(:skills)
          .where(
            skills: {
              id: params[:skill_id]
            }
          )
    end

    @guides =
      @guides.order(
        :priority,
        :name
      )
  end

  def new
    @guide = Guide.new
  end

  def create
    @guide = Guide.new(guide_params)

    if @guide.save
      redirect_to(
        guides_path,
        notice: "Guide created successfully."
      )
    else
      Rails.logger.info(
        "Guide creation errors: #{@guide.errors.full_messages.join(', ')}"
      )

      render :new,
             status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @guide.update(guide_params)
      redirect_to(
        guides_path,
        notice: "Guide updated successfully."
      )
    else
      render :edit,
             status: :unprocessable_entity
    end
  end

  # Cambia el estado Active / Inactive del guía.
  #
  # Al activar:
  # - Guide reinicia fairness_started_on automáticamente.
  # - Se agregan GuideDays faltantes a WorkDays actuales/futuros
  #   que todavía estén en estado draft.
  #
  # Al desactivar:
  # - El historial permanece intacto.
  # - fairness_started_on no se borra.
  # - No se modifican WorkDays históricos.
  def toggle_active
    new_status = !@guide.active?

    ActiveRecord::Base.transaction do
      @guide.update!(
        active: new_status
      )

      sync_guide_with_draft_work_days if new_status
    end

    message =
      if new_status
        "Guide activated. A new fairness cycle started on " \
        "#{@guide.fairness_started_on}."
      else
        "Guide deactivated. Fairness history was preserved."
      end

    redirect_to(
      guides_path,
      notice: message
    )
  rescue ActiveRecord::RecordInvalid => e
    redirect_to(
      guides_path,
      alert: e.record.errors.full_messages.to_sentence
    )
  end

  private

  def set_guide
    @guide = Guide.find(params[:id])
  end

  # Cuando un guía es activado después de que un WorkDay
  # ya fue creado, ese WorkDay podría no contener un GuideDay
  # para él.
  #
  # Agregamos únicamente los registros faltantes para:
  # - hoy o fechas futuras;
  # - WorkDays todavía en draft.
  #
  # Los rolls generated o published NO se modifican
  # automáticamente para evitar alterar operaciones ya procesadas.
  def sync_guide_with_draft_work_days
    WorkDay
      .where("date >= ?", Date.current)
      .draft
      .find_each do |work_day|

      work_day.guide_days.find_or_create_by!(
        guide: @guide
      ) do |guide_day|
        guide_day.status = :standby
      end
    end
  end

  # :active y :fairness_started_on se excluyen intencionalmente.
  #
  # active solo puede cambiar mediante toggle_active.
  # fairness_started_on es administrado automáticamente por Guide.
  def guide_params
    params.require(:guide).permit(
      :name,
      :priority,
      :day_off_balance,
      :day_off_balance_updated_at,
      skill_ids: []
    )
  end
end