class ScopeTransportRatesToCompanies < ActiveRecord::Migration[8.1]
  def up
    add_reference :transport_rates, :transport_company, foreign_key: true
    remove_index :transport_rates, [:location, :size_category]

    # Copy each current tariff to every registered company before removing the
    # shared rows. Existing bus assignment cost snapshots remain untouched.
    execute <<~SQL
      INSERT INTO transport_rates
        (transport_company_id, location, size_category, amount_cents, created_at, updated_at)
      SELECT companies.id, rates.location, rates.size_category, rates.amount_cents,
        rates.created_at, rates.updated_at
      FROM transport_companies companies
      CROSS JOIN transport_rates rates
      WHERE rates.transport_company_id IS NULL
    SQL
    execute "DELETE FROM transport_rates WHERE transport_company_id IS NULL"

    change_column_null :transport_rates, :transport_company_id, false
    add_index :transport_rates,
      [:transport_company_id, :location, :size_category],
      unique: true, name: "one_transport_rate_per_company_outing_size"
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "Las tarifas distintas de varias empresas no se pueden reducir a una tarifa global"
  end
end
