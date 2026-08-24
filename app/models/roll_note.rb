class RollNote < ApplicationRecord
  belongs_to :work_day
  belongs_to :created_by,
             class_name: "User"

  has_many :roll_note_guide_days,
           dependent: :destroy

  has_many :guide_days,
           through: :roll_note_guide_days

  enum :note_type, {
    incident: 0,
    observation: 1
  }

  validates :note,
            presence: true

  validates :note_type,
            presence: true

  validate :guide_days_belong_to_work_day

  private

  def guide_days_belong_to_work_day
    return if work_day.blank?

    guide_days.each do |guide_day|
      next if guide_day.work_day_id == work_day_id

      errors.add(
        :guide_days,
        "must belong to the selected work day"
      )
    end
  end
end