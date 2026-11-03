class AddDriverRequirementsToWorkDays < ActiveRecord::Migration[8.1]
  def change
    add_column :work_days, :drivers_requested_by_location, :jsonb,
      default: {}, null: false
  end
end
