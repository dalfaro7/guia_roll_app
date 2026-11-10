class SaraGuidesController < ApplicationController
  before_action :require_sara_operator!
  before_action :require_compensation_operator!, only: [:edit, :update]
  before_action :set_guide, only: [:edit, :update, :toggle_active]

  REQUIRED_SKILLS = %w[ClassIV address_Sarapiqui].freeze

  def index
    @guides = Guide.where(priority: 6).includes(:skills).order(:name)
  end

  def new
    @guide = Guide.new(priority: 6, active: false,
      pay_category: "freelance_regular")
    @guide.skills = required_skills
  end

  def create
    @guide = Guide.new(name: guide_params[:name].to_s.strip, priority: 6,
      active: false, pay_category: "freelance_regular")
    Guide.transaction do
      @guide.save!
      @guide.skills = selected_skills
      audit!(action: "create_sara_reserve_guide", auditable: @guide,
        metadata: { priority: 6, skill_ids: @guide.skill_ids })
    end
    redirect_to sara_guides_path, notice: "Guía de prioridad 6 creado e inactivo."
  rescue ActiveRecord::RecordInvalid, SaraManualAssignment::InvalidSelection => error
    redirect_to new_sara_guide_path, alert: error.message
  end

  def edit
  end

  def update
    before = { name: @guide.name, skill_ids: @guide.skill_ids.sort }
    Guide.transaction do
      @guide.update!(name: guide_params[:name].to_s.strip)
      @guide.skills = selected_skills
      audit!(action: "update_sara_reserve_guide", auditable: @guide,
        metadata: { before: before,
          after: { name: @guide.name, skill_ids: @guide.skill_ids.sort } })
    end
    redirect_to sara_guides_path, notice: "Guía de prioridad 6 actualizado."
  rescue ActiveRecord::RecordInvalid, SaraManualAssignment::InvalidSelection => error
    redirect_to edit_sara_guide_path(@guide), alert: error.message
  end

  def toggle_active
    Guide.transaction do
      before = @guide.active?
      @guide.update!(active: !before)
      if @guide.active?
        WorkDay.where(date: Date.current..).draft.find_each do |work_day|
          work_day.guide_days.find_or_create_by!(guide: @guide) do |day|
            day.status = :standby
          end
        end
      end
      audit!(action: "toggle_sara_reserve_guide", auditable: @guide,
        metadata: { before: before, after: @guide.active? })
    end
    redirect_to sara_guides_path,
      notice: @guide.active? ? "Guía activado." : "Guía desactivado."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to sara_guides_path, alert: error.message
  end

  private

  def set_guide
    @guide = Guide.where(priority: 6).find(params[:id])
  end

  def guide_params
    params.require(:guide).permit(:name, skill_ids: [])
  end

  def required_skills
    REQUIRED_SKILLS.map { |name| Skill.find_or_create_by!(name: name) }
  end

  def selected_skills
    ids = Array(guide_params[:skill_ids]).map(&:to_s).reject(&:blank?)
    unless ids.all? { |id| id.match?(/\A\d+\z/) }
      raise SaraManualAssignment::InvalidSelection, "Habilidad inválida."
    end
    ids = ids.map(&:to_i).uniq
    skills = Skill.where(id: ids).to_a
    unless skills.size == ids.size
      raise SaraManualAssignment::InvalidSelection, "Habilidad inválida."
    end

    (skills + required_skills).uniq
  end
end
