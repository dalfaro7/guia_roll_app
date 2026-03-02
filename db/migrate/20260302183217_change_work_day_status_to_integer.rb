class ChangeWorkDayStatusToInteger < ActiveRecord::Migration[7.0]
  def up
    add_column :work_days, :status_tmp, :integer, default: 0

    WorkDay.reset_column_information
    WorkDay.find_each do |wd|
      wd.update_column(:status_tmp, 0) if wd.status == "draft"
      wd.update_column(:status_tmp, 1) if wd.status == "generated"
      wd.update_column(:status_tmp, 2) if wd.status == "published"
    end

    remove_column :work_days, :status
    rename_column :work_days, :status_tmp, :status
  end
end
