class AddStatusNoteToGuideDays < ActiveRecord::Migration[8.1]
  def change
    add_column :guide_days, :status_note, :text
  end
end
