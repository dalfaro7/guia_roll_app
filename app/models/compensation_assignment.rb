class CompensationAssignment < ApplicationRecord
  GUIDE_ROLES = %w[river_guide tl_balsa tl_sara hg_balsa hg_sara safety_kayak photographer].freeze
  DRIVER_ROLES = %w[driver_la_fortuna driver_bodega driver_hg driver_per_trip].freeze
  PHOTO_TASKS = %w[none take_and_send send_only].freeze
  PHOTO_SENDING_LOCATIONS = %w[PM Sara-3&4 Sara-3 Sara-4].freeze
  STATUSES = %w[planned performed canceled no_show].freeze

  belongs_to :departure
  belongs_to :guide, optional: true
  belongs_to :driver, optional: true
  belongs_to :guide_day, optional: true
  belongs_to :updated_by, class_name: "User", optional: true
  has_many :compensation_lines, dependent: :destroy
  has_one :bus_assignment, dependent: :nullify

  validates :status, inclusion: { in: STATUSES }
  validates :photo_task, inclusion: { in: PHOTO_TASKS }
  validates :source, inclusion: { in: %w[automatic manual] }
  validate :one_person_and_correct_role
  validate :at_most_two_departures_per_day
  validate :photo_responsibility
  validate :leader_role_matches_departure

  scope :payable, -> { where(status: "performed") }
  scope :active, -> { where.not(status: %w[canceled no_show]) }

  def person
    guide || driver
  end

  def total_cents
    compensation_lines.sum(:amount_cents)
  end

  def guide?
    guide_id.present?
  end

  def driver?
    driver_id.present?
  end

  private

  def one_person_and_correct_role
    if guide.present? == driver.present?
      errors.add(:base, "Debe asignar un guía o un chofer, pero no ambos")
    elsif guide.present? && !GUIDE_ROLES.include?(role_code)
      errors.add(:role_code, "no corresponde a un guía")
    elsif driver.present? && !DRIVER_ROLES.include?(role_code)
      errors.add(:role_code, "no corresponde a un chofer")
    end
  end

  def at_most_two_departures_per_day
    return if departure.blank? || person.blank? || role_code == "host" ||
      %w[canceled no_show].include?(status)

    peer_scope = self.class.joins(:departure)
      .where(departures: { work_day_id: departure.work_day_id })
      .where(guide_id: guide_id, driver_id: driver_id)
      .where.not(role_code: "host")
      .where.not(status: %w[canceled no_show])
    peer_scope = peer_scope.where.not(id: id) if persisted?
    errors.add(:base, "Una persona puede tener como máximo dos salidas al día") if peer_scope.count >= 2
  end

  def leader_role_matches_departure
    return unless departure && role_code.to_s.start_with?("tl_", "hg_")

    expected = Departure.leader_rate_suffix_for(departure.location)
    errors.add(:role_code, "no corresponde a la salida #{departure.label}") unless
      expected && role_code.end_with?("_#{expected}")
  end

  def photo_responsibility
    return if departure.blank? || %w[canceled no_show].include?(status)

    if driver? && (photo_task != "none" || principal_photographer?)
      errors.add(:base, "Un chofer no puede tener tareas de fotografía")
      return
    end

    if role_code == "photographer"
      errors.add(:photo_task, "El fotógrafo ya toma fotos") unless photo_task == "none"
    elsif principal_photographer?
      errors.add(:principal_photographer, "Debe ser fotógrafo")
    end

    if photo_task == "send_only" && (role_code != "river_guide" ||
        !PHOTO_SENDING_LOCATIONS.include?(departure.location))
      errors.add(:photo_task, "Solo un guía de río en PM o Sarapiquí puede enviar fotos")
    end

    if role_code == "safety_kayak" && photo_task == "take_and_send"
      errors.add(:photo_task, "El kayak de seguridad solo puede enviar fotos ajenas")
    end

    if %w[tl_balsa tl_sara hg_balsa hg_sara].include?(role_code) &&
        (photo_task != "none" || also_drives? || bus_guide?)
      errors.add(:base, "TL y HG solo cobran su función principal")
    end

    other_active = departure.compensation_assignments.active.where.not(id: id)
    if role_code == "photographer" && !principal_photographer? &&
        !other_active.where(role_code: "photographer", principal_photographer: true).exists?
      errors.add(:principal_photographer, "Debe designar un fotógrafo principal")
    end
    if photo_task != "none" && other_active.where(role_code: "photographer").exists?
      errors.add(:photo_task, "El envío corresponde al fotógrafo principal")
    elsif photo_task != "none" && other_active.where.not(photo_task: "none").exists?
      errors.add(:photo_task, "Ya existe un responsable de fotos en esta salida")
    end
    if role_code == "photographer" && other_active.where.not(photo_task: "none").exists?
      errors.add(:base, "Quite la tarea de fotos del guía antes de asignar un fotógrafo")
    end
  end
end
