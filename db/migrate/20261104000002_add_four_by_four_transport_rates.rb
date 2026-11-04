class AddFourByFourTransportRates < ActiveRecord::Migration[8.1]
  def up
    add_column :transport_rates, :vehicle_kind, :string,
      null: false, default: "bus"
    add_check_constraint :transport_rates,
      "vehicle_kind = 'bus' OR (vehicle_kind = 'four_by_four' AND size_category = 'small')",
      name: "transport_rate_vehicle_kind_valid"
    remove_index :transport_rates, name: "one_transport_rate_per_company_outing_size"
    add_index :transport_rates,
      [:transport_company_id, :location, :vehicle_kind, :size_category],
      unique: true, name: "one_transport_rate_per_company_outing_vehicle"

    %w[Balsa Sara-3&4 PM Privado].each do |location|
      execute <<~SQL
        INSERT INTO transport_rates
          (transport_company_id, location, vehicle_kind, size_category,
           amount_cents, created_at, updated_at)
        SELECT id, '#{location}', 'four_by_four', 'small', 12000,
          CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        FROM transport_companies
        ON CONFLICT DO NOTHING
      SQL
    end
  end

  def down
    remove_index :transport_rates, name: "one_transport_rate_per_company_outing_vehicle"
    execute "DELETE FROM transport_rates WHERE vehicle_kind = 'four_by_four'"
    remove_check_constraint :transport_rates, name: "transport_rate_vehicle_kind_valid"
    remove_column :transport_rates, :vehicle_kind
    add_index :transport_rates,
      [:transport_company_id, :location, :size_category],
      unique: true, name: "one_transport_rate_per_company_outing_size"
  end
end
