class CompensationSettlement < ApplicationRecord
  belongs_to :guide, optional: true
  belongs_to :driver, optional: true
  belongs_to :paid_by, class_name: "User", optional: true
  has_many :compensation_adjustments, dependent: :restrict_with_error
  has_many :compensation_settlement_items, dependent: :restrict_with_error

  validates :week_start, :week_end, presence: true
  validate :one_person
  validate :wednesday_to_tuesday

  def person
    guide || driver
  end

  def paid?
    paid_at.present?
  end

  def mark_paid!(user)
    with_lock do
      raise "El período aún no está cerrado" if closed_at.blank?
      raise "El período ya fue pagado" if paid?
      if compensation_settlement_items.joins(:compensation_assignment)
          .where.not(compensation_assignments: { pricing_error: nil }).exists?
        raise "Hay asignaciones sin valorar en este período"
      end

      update!(paid_at: Time.current, paid_by: user)
    end
  end

  private

  def one_person
    errors.add(:base, "Debe tener exactamente una persona") if guide.present? == driver.present?
  end

  def wednesday_to_tuesday
    return if week_start.blank? || week_end.blank?

    unless week_start.wednesday? && week_end == week_start + 6.days
      errors.add(:week_start, "El período debe ir de miércoles a martes")
    end
  end
end
