class DropAssignments < ActiveRecord::Migration[8.1]
  def change
    drop_table :assignments
  end
end
