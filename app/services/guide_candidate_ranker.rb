class GuideCandidateRanker
  def initialize(work_day:, skill_ids: [])
    @work_day = work_day
    @skill_ids = Array(skill_ids).reject(&:blank?).map(&:to_i)
  end

  # Devuelve todos los candidatos standby que cumplen
  # con los skills solicitados.
  def standby_candidates
    candidates.select do |guide_day|
      guide_meets_required_skills?(guide_day.guide)
    end
  end

  # Devuelve únicamente el candidato mejor posicionado
  # según la política centralizada de fairness.
  def next_candidate
    standby_candidates.first
  end

  private

  # Ordena los GuideDay disponibles usando exactamente
  # la misma lógica de fairness que RoleGeneratorV2.
  #
  # Esto evita que la generación normal y el force assign
  # produzcan órdenes diferentes para los mismos guías.
  def candidates
    GuideDay
      .available_for_date(@work_day.date)
      .where(work_day: @work_day)
      .includes(guide: :skills)
      .sort_by do |guide_day|
        RollFairnessPolicy.ranking_key_for(
          guide_day.guide,
          before_date: @work_day.date
        )
      end
  end

  # Verifica que el guía tenga todos los skills requeridos.
  #
  # Por ahora mantenemos esta lógica intacta, ya que acordamos
  # no modificar el comportamiento de skills en esta etapa.
  def guide_meets_required_skills?(guide)
    return true if @skill_ids.empty?

    guide_skill_ids = guide.skills.map(&:id)

    (@skill_ids - guide_skill_ids).empty?
  end
end