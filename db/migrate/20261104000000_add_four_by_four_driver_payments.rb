class AddFourByFourDriverPayments < ActiveRecord::Migration[8.1]
  def up
    add_column :buses, :vehicle_kind, :string, null: false, default: "bus"
    add_check_constraint :buses, "vehicle_kind IN ('bus', 'four_by_four')",
      name: "bus_vehicle_kind_valid"

    add_column :transport_companies, :internal_fleet, :boolean,
      null: false, default: false
    execute <<~SQL
      UPDATE transport_companies SET internal_fleet = TRUE
      WHERE LOWER(TRIM(name)) = 'arc'
    SQL

    change_column_null :drivers, :transport_company_id, true
    add_column :drivers, :payment_mode, :string, null: false, default: "none"
    add_check_constraint :drivers,
      "payment_mode IN ('none', 'per_trip', 'daily_hg', 'round_trip')",
      name: "driver_payment_mode_valid"

    add_column :bus_assignments, :outing_variant, :string
    add_reference :bus_assignments, :compensation_assignment,
      foreign_key: true, index: { unique: true, name: "one_transport_per_driver_payment" }
    remove_index :bus_assignments, name: "one_bus_assignment_per_day"
    add_index :bus_assignments, [:bus_id, :work_day_id, :location],
      unique: true, name: "one_bus_per_day_and_outing"

    CompensationRate.reset_column_information
    execute <<~SQL
      INSERT INTO compensation_rates (code, amount_cents, effective_at, created_at, updated_at)
      VALUES ('driver_per_trip', 2000, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "Second 4x4 assignments may exist; restoring the old daily unique index would lose data"
  end
end
