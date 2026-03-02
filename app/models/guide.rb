class Guide < ApplicationRecord
  
  has_many :guide_days, dependent: :destroy
  has_one :monthly_balance, dependent: :destroy
  validates :name, presence: true
  validates :priority, presence: true

  scope :active, -> { where(active: true) }
  after_update :reset_future_generated_days, if: :saved_change_to_priority?


  private

  def reset_future_generated_days
  future_days = WorkDay
                  .where("date >= ?", Date.today)
                  .generated

  future_days.find_each do |day|
    RoleResetService.new(day).call
  end
end
end
