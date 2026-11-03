class AddTransportCompaniesAndBusDetails < ActiveRecord::Migration[8.1]
  def up
    create_table :transport_companies do |t|
      t.string :name, null: false
      t.timestamps
    end
    add_index :transport_companies, "LOWER(name)", unique: true,
      name: "unique_transport_company_name"

    add_reference :buses, :transport_company, foreign_key: true
    add_column :buses, :size_category, :string
    add_reference :drivers, :transport_company, foreign_key: true
    add_column :drivers, :phone, :string
    add_reference :bus_assignments, :driver, foreign_key: true

    execute <<~SQL
      INSERT INTO transport_companies (name, created_at, updated_at)
      SELECT DISTINCT BTRIM(company), CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM buses
      WHERE NULLIF(BTRIM(company), '') IS NOT NULL
    SQL
    execute <<~SQL
      UPDATE buses
      SET transport_company_id = transport_companies.id
      FROM transport_companies
      WHERE BTRIM(buses.company) = transport_companies.name
    SQL

    # Asdrúbal is the sole existing production driver and belongs to ARC.
    execute <<~SQL
      UPDATE drivers
      SET transport_company_id = transport_companies.id
      FROM transport_companies
      WHERE LOWER(BTRIM(drivers.name)) IN ('asdrubal', 'asdrúbal')
        AND transport_companies.name = 'ARC'
    SQL

    if select_value("SELECT COUNT(*) FROM buses WHERE transport_company_id IS NULL").to_i.positive? ||
        select_value("SELECT COUNT(*) FROM drivers WHERE transport_company_id IS NULL").to_i.positive?
      execute <<~SQL
        INSERT INTO transport_companies (name, created_at, updated_at)
        VALUES ('Empresa pendiente de asignar', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        ON CONFLICT DO NOTHING
      SQL
      execute <<~SQL
        UPDATE buses SET transport_company_id = (
          SELECT id FROM transport_companies WHERE name = 'Empresa pendiente de asignar'
        ) WHERE transport_company_id IS NULL
      SQL
      execute <<~SQL
        UPDATE drivers SET transport_company_id = (
          SELECT id FROM transport_companies WHERE name = 'Empresa pendiente de asignar'
        ) WHERE transport_company_id IS NULL
      SQL
    end

    execute <<~SQL
      UPDATE buses SET size_category = CASE
        WHEN capacity BETWEEN 1 AND 15 THEN 'small'
        WHEN capacity >= 20 THEN 'large'
      END
    SQL
    invalid = select_value("SELECT COUNT(*) FROM buses WHERE size_category IS NULL").to_i
    raise ActiveRecord::MigrationError, "#{invalid} buses requieren capacidad válida: 1–15 o 20 o más" if invalid.positive?

    duplicate_days = select_value(<<~SQL).to_i
      SELECT COUNT(*) FROM (
        SELECT bus_id, work_day_id FROM bus_assignments
        GROUP BY bus_id, work_day_id HAVING COUNT(*) > 1
      ) duplicates
    SQL
    raise ActiveRecord::MigrationError, "Hay buses repetidos en una misma fecha" if duplicate_days.positive?

    change_column_null :buses, :transport_company_id, false
    change_column_null :buses, :size_category, false
    change_column_null :drivers, :transport_company_id, false

    add_check_constraint :buses,
      "(size_category = 'small' AND capacity BETWEEN 1 AND 15) OR (size_category = 'large' AND capacity >= 20)",
      name: "bus_size_matches_capacity"
    add_index :bus_assignments, [:bus_id, :work_day_id], unique: true,
      name: "one_bus_assignment_per_day"
  end

  def down
    remove_index :bus_assignments, name: "one_bus_assignment_per_day"
    remove_check_constraint :buses, name: "bus_size_matches_capacity"
    remove_reference :bus_assignments, :driver, foreign_key: true
    remove_column :drivers, :phone
    remove_reference :drivers, :transport_company, foreign_key: true
    remove_column :buses, :size_category
    remove_reference :buses, :transport_company, foreign_key: true
    drop_table :transport_companies
  end
end
