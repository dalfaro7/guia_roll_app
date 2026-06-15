class OfficeOvertime < ApplicationRecord
  belongs_to :office_employee

  validates :date, presence: true
  validates :minutes, numericality: { greater_than: 0 }
  validates :reason, presence: true

  def formatted_time
    hours = minutes / 60
    remaining_minutes = minutes % 60

    format("%02d:%02d", hours, remaining_minutes)
  end
end
