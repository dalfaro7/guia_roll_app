class OfficeVacationCredit < ApplicationRecord
  belongs_to :office_employee

  has_one :office_employee_day,
          dependent: :nullify

  validates :date, presence: true
  validates :source, presence: true

  validates :office_employee_id,
            uniqueness: {
              scope: [:date, :source],
              message: "ya tiene un crédito de vacaciones de este origen para esta fecha"
            }

  scope :available, -> {
    where(used: false).order(:date, :id)
  }

  scope :used, -> {
    where(used: true)
  }

  scope :legacy, -> {
    where(source: "legacy")
  }

  def available?
    !used?
  end

  def mark_as_used!(used_on:)
    update!(
      used: true,
      used_on: used_on
    )
  end

  def release!
    update!(
      used: false,
      used_on: nil
    )
  end
end
