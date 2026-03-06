class Guide < ApplicationRecord

  has_many :guide_skills, dependent: :destroy
  has_many :skills, through: :guide_skills
  has_many :guide_days, dependent: :destroy
  has_many :monthly_balances, dependent: :destroy
  has_many :manual_day_offs, dependent: :destroy


  validates :name, presence: true
  validates :priority, presence: true

  scope :active, -> { where(active: true) }

  after_update :reset_future_generated_days, if: :saved_change_to_priority?

  before_save :update_day_off_balance_timestamp

  def consume_day_off!
  self.day_off_balance ||= 0
  self.day_off_balance -= 1
  save!
  end


  
  def reset_future_generated_days
    future_days = WorkDay
                    .where("date >= ?", Date.today)
                    .generated

    future_days.find_each do |day|
      RoleResetService.new(day).call
    end
  end

  def update_day_off_balance_timestamp
    if will_save_change_to_day_off_balance?
      self.day_off_balance_updated_at = Time.current
    end
  end

end