class RollNoteGuideDay < ApplicationRecord
  belongs_to :roll_note
  belongs_to :guide_day

  validates :guide_day_id,
            uniqueness: {
              scope: :roll_note_id
            }
end