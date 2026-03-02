class MonthlyBalance < ApplicationRecord
  belongs_to :guide

  validates :month, presence: true

  def self.for_month(date)
    where(month: date.beginning_of_month)
  end
end
