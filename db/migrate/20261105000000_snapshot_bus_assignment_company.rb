class SnapshotBusAssignmentCompany < ActiveRecord::Migration[8.1]
  def up
    add_reference :bus_assignments, :transport_company_snapshot,
      foreign_key: { to_table: :transport_companies }
    add_column :bus_assignments, :transport_company_name_snapshot, :string

    execute <<~SQL
      UPDATE bus_assignments
      SET transport_company_snapshot_id = buses.transport_company_id,
          transport_company_name_snapshot = transport_companies.name
      FROM buses
      JOIN transport_companies ON transport_companies.id = buses.transport_company_id
      WHERE bus_assignments.bus_id = buses.id
    SQL

    change_column_null :bus_assignments, :transport_company_snapshot_id, false
    change_column_null :bus_assignments, :transport_company_name_snapshot, false
  end

  def down
    remove_column :bus_assignments, :transport_company_name_snapshot
    remove_reference :bus_assignments, :transport_company_snapshot,
      foreign_key: { to_table: :transport_companies }
  end
end
