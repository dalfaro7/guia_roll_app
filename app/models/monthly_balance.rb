class MonthlyBalance < ApplicationRecord
  belongs_to :guide

  validates :month, presence: true

  # Devuelve los balances correspondientes al mes de la fecha indicada.
  #
  # MonthlyBalance se mantiene como información histórica/estadística.
  # NO es la fuente de verdad para determinar la posición del guía
  # dentro del fairness del roll.
  def self.for_month(date)
    where(
      month: date.beginning_of_month
    )
  end
end
