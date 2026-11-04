class AddSuperadminToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :superadmin, :boolean, null: false, default: false
    add_check_constraint :users, "superadmin = FALSE OR role = 1",
      name: "users_superadmin_requires_admin"
  end
end
