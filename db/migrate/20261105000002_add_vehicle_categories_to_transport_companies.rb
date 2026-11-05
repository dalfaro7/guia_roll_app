class AddVehicleCategoriesToTransportCompanies < ActiveRecord::Migration[8.1]
  def up
    add_column :transport_companies, :vehicle_categories, :string, array: true,
      null: false, default: %w[bus_small bus_large]

    execute <<~SQL
      UPDATE transport_companies
      SET vehicle_categories = ARRAY['bus_small', 'bus_large', 'four_by_four']
      WHERE internal_fleet = TRUE
    SQL
  end

  def down
    remove_column :transport_companies, :vehicle_categories
  end
end
