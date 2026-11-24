class WorkDay < ApplicationRecord
  class UnsafeDeletion < StandardError; end

  # Check financial dependencies before destroying any operational children.
  has_many :departures, dependent: :restrict_with_error
  has_many :work_day_versions, dependent: :destroy
  has_many :guide_days, dependent: :destroy
  has_many :guides, through: :guide_days
  has_many :location_slots, dependent: :destroy
  has_many :bus_assignments, dependent: :destroy
  has_many :audit_logs, dependent: :nullify
  has_many :roll_notes, dependent: :destroy

  accepts_nested_attributes_for :guide_days,
                                update_only: true

  after_create :initialize_guide_days

  validates :date, presence: true

  validates :guides_requested,
            numericality: {
              greater_than_or_equal_to: 0
            },
            allow_nil: true

  validate :date_cannot_be_in_the_past

  enum :status, {
    draft: 0,
    generated: 1,
    published: 2
  }

  # Devuelve los guías standby del roll publicado
  # usando exactamente la misma política de fairness
  # que la generación y el force assign.
  def standby_guides_for_published_roll
    GuideCandidateRanker.new(
      work_day: self,
      skill_ids: []
    ).standby_candidates
  end

  def buses_for(location)
    bus_assignments
      .includes(:bus)
      .where(location: location)
  end

  def passengers_for(location)
    location_slots
      .find_by(location: location)
      &.passengers
      .to_i
  end

  def drivers_requested_for(location)
    drivers_requested_by_location.fetch(location.to_s, 0).to_i
  end

  def bus_capacity_for(location)
    buses_for(location).joins(:bus)
      .where(buses: { vehicle_kind: "bus" })
      .sum("buses.capacity")
  end

  def four_by_four_guide_capacity_for(location)
    buses_for(location).joins(:bus)
      .where(buses: { vehicle_kind: "four_by_four" })
      .sum("buses.capacity")
  end

  def four_by_four_guide_spaces_remaining_for(location)
    four_by_four_guide_capacity_for(location) -
      buses_for(location).joins(:bus)
        .where(buses: { vehicle_kind: "four_by_four" })
        .sum(:seats_assigned)
  end

  def seats_remaining_for(location)
    bus_capacity_for(location) -
      passengers_for(location)
  end

  # Al crear un WorkDay solo se incluyen guías activos.
  #
  # Esto es importante porque un guía inactivo no debe
  # entrar en disponibilidad ni competir por fairness.
  def initialize_guide_days
    Guide.active.find_each do |guide|
      guide_days.create!(
        guide: guide,
        status: :standby
      )
    end
  end

  # Genera el roll utilizando RoleGeneratorV2.
  #
  # Toda la lógica de fairness se encuentra centralizada
  # en RollFairnessPolicy.
  def generate_roles!
    raise "WorkDay must be draft" unless draft?

    RoleGeneratorV2.new(self).generate!

    log_event(
      "generate_roles",
      "draft",
      "generated"
    )
  end

  def calculated_guides_requested
    location_slots.count
  end

  # Cada salida cubierta cuenta por separado, aunque la haga el mismo guía.
  # Las tareas asignadas no ocupan un puesto de guía.
  def assigned_roll_count
    RollOutingRoster.new(self).entries.count
  end

  def roll_coverage_errors
    RollOutingRoster.new(self).coverage_errors
  end

  def required_roll_count
    location_slots.count
  end

  def publish!
    with_lock do
      raise "Only generated days can be published" unless generated?
      coverage_errors = roll_coverage_errors
      if coverage_errors.any?
        errors.add(:base, "Asignaciones incompletas por salida: #{coverage_errors.join("; ")}")
        raise ActiveRecord::RecordInvalid, self
      end

      bus_assignments.order(:id).lock.each(&:refresh_rate_for_publication!)
      previous_status = status
      update!(
        status: :published,
        published_at: Time.current
      )
      log_event("publish", previous_status, "published")
    end
  end

  def unpublish!
    raise "Only published days can be unpublished" unless published?

    previous_status = status

    update!(
      status: :generated,
      published_at: nil
    )

    log_event(
      "unpublish",
      previous_status,
      "generated"
    )
  end

  def reset_roll!
    raise "Cannot reset draft day" if draft?

    RoleResetService.new(self).call
  end

  def regenerate_with_new_count!(new_count)
    raise "Cannot regenerate draft days" if draft?

    new_count = new_count.to_i

    previous_status = status
    previous_count = guides_requested

    if new_count != location_slots.count
      raise ArgumentError,
            "new_count must match location_slots.count"
    end

    ActiveRecord::Base.transaction do
      RoleResetService.new(self).call

      update!(
        guides_requested: new_count
      )

      log_event(
        "regenerate_with_new_count",
        previous_status,
        "draft",
        previous_count,
        new_count
      )

      generate_roles!
    end
  end

  def force_delete!
    with_lock do
      reason = deletion_block_reason
      raise UnsafeDeletion, reason if reason

      remove_unpublished_plan! if generated?
      RoleResetService.new(self).revert_only_balances
      destroy!
    end
  end

  def deletion_block_reason
    return "Una programación publicada no se puede eliminar." if published?
    return (departures.exists? ? "Este borrador tiene valoraciones vinculadas y no se puede eliminar." : nil) if draft?
    return "Solo se eliminan programaciones generadas para fechas futuras." unless date > Date.current
    if work_day_versions.where("snapshot ->> 'event' = ?", "publish").exists?
      return "Esta programación ya fue publicada y conserva historial."
    end
    if departures.where.not(status: "scheduled").exists? ||
        departures.where.not(closed_at: nil).exists?
      return "Esta programación tiene salidas cerradas o canceladas."
    end

    assignments = CompensationAssignment.joins(:departure)
      .where(departures: { work_day_id: id })
    if assignments.where.not(status: %w[planned canceled]).exists?
      return "Esta programación tiene trabajo o pagos realizados."
    end
    assignment_ids = assignments.select(:id)
    if bus_assignments.where.not(compensation_assignment_id: nil)
        .where.not(compensation_assignment_id: assignment_ids).exists?
      return "Hay pagos de chofer vinculados a otra programación."
    end
    if CompensationAdjustment.where(source_assignment_id: assignment_ids).exists?
      return "Esta programación tiene ajustes contables vinculados."
    end
    week_start = Compensation::SettlementService.week_start(date)
    if CompensationSettlement.where(week_start: week_start)
        .where("closed_at IS NOT NULL OR paid_at IS NOT NULL").exists?
      return "La semana de esta programación ya tiene pagos cerrados."
    end
    if CompensationSettlementItem.joins(:compensation_settlement)
        .where(compensation_assignment_id: assignment_ids)
        .where("compensation_settlements.closed_at IS NOT NULL OR compensation_settlements.paid_at IS NOT NULL").exists?
      return "Esta programación tiene pagos cerrados vinculados."
    end

    nil
  end

  private

  def remove_unpublished_plan!
    assignments = CompensationAssignment.joins(:departure)
      .where(departures: { work_day_id: id })
    assignment_ids = assignments.pluck(:id)
    settlement_ids = CompensationSettlementItem
      .where(compensation_assignment_id: assignment_ids)
      .distinct.pluck(:compensation_settlement_id)

    CompensationSettlementItem.where(compensation_assignment_id: assignment_ids).delete_all
    # BusAssignment callbacks cancel payments but cannot remove a first 4x4 leg
    # before PM. Here all planned payments are removed together below.
    bus_assignments.delete_all
    assignments.find_each(&:destroy!)
    Compensation::SettlementService.refresh_for(self)
    CompensationSettlement.where(id: settlement_ids).find_each do |settlement|
      next if settlement.compensation_settlement_items.exists? ||
        settlement.compensation_adjustments.exists?

      raise UnsafeDeletion, "Quedó un pago planificado sin conciliar." unless
        settlement.amount_cents.zero?
      settlement.destroy!
    end
    departures.destroy_all
  end

  def log_event(
    event,
    previous_status,
    new_status,
    previous_count = nil,
    new_count = nil
  )
    WorkDayVersion.create!(
      work_day: self,
      snapshot: {
        event: event,
        previous_status: previous_status,
        new_status: new_status,
        previous_guides_requested: previous_count,
        new_guides_requested: new_count,
        performed_at: Time.current
      }
    )
  end

  def date_cannot_be_in_the_past
    return if date.blank?
    return unless new_record? || will_save_change_to_date?

    if date < Date.current
      errors.add(
        :date,
        "cannot be in the past"
      )
    end
  end
end
