class AddCostToBusAssignments < ActiveRecord::Migration[8.1]
  def change
    add_column :bus_assignments, :cost_cents, :integer, default: 12_000, null: false
    add_check_constraint :bus_assignments, "cost_cents >= 0",
      name: "bus_assignment_cost_nonnegative"
  end
end
