class AddTransportCostAdjustmentsToBusAssignments < ActiveRecord::Migration[8.1]
  def up
    add_column :bus_assignments, :base_cost_cents, :integer, default: 0, null: false
    add_column :bus_assignments, :discount_cents, :integer, default: 0, null: false
    add_column :bus_assignments, :discount_reason, :text

    execute "UPDATE bus_assignments SET base_cost_cents = cost_cents"

    add_check_constraint :bus_assignments, "base_cost_cents >= 0",
      name: "bus_assignment_base_cost_nonnegative"
    add_check_constraint :bus_assignments, "discount_cents >= 0 AND discount_cents <= base_cost_cents",
      name: "bus_assignment_discount_within_base"
    add_check_constraint :bus_assignments, "cost_cents = base_cost_cents - discount_cents",
      name: "bus_assignment_cost_matches_discount"
  end

  def down
    remove_check_constraint :bus_assignments, name: "bus_assignment_cost_matches_discount"
    remove_check_constraint :bus_assignments, name: "bus_assignment_discount_within_base"
    remove_check_constraint :bus_assignments, name: "bus_assignment_base_cost_nonnegative"
    remove_column :bus_assignments, :discount_reason
    remove_column :bus_assignments, :discount_cents
    remove_column :bus_assignments, :base_cost_cents
  end
end
