class TrackScheduleCanceledCompensationAssignments < ActiveRecord::Migration[8.1]
  def change
    add_column :compensation_assignments, :canceled_by_schedule,
      :boolean, default: false, null: false
  end
end
