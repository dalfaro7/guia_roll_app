class OfficeHoliday < ApplicationRecord
  validates :date, presence: true, uniqueness: true
  validates :name, presence: true

  scope :double_pay, -> { where(double_pay: true) }
end
