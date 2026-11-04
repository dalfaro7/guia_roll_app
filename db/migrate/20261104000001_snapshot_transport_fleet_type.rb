class SnapshotTransportFleetType < ActiveRecord::Migration[8.1]
  def change
    add_column :bus_assignments, :internal_fleet_snapshot, :boolean
  end
end
