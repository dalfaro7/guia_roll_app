class CreateCompensationSystem < ActiveRecord::Migration[8.1]
  INITIAL_RATES = {
    guide_apprentice: 4_000,
    guide_regular: 5_000,
    guide_invoice: 6_000,
    tl_balsa: 7_000,
    tl_sara: 6_000,
    hg_balsa: 9_000,
    hg_sara: 6_000,
    safety_kayak: 5_000,
    photographer: 5_000,
    driver_la_fortuna: 4_000,
    driver_bodega: 2_000,
    driver_hg: 4_500,
    bonus_guide_drives: 1_400,
    bonus_photo_take_and_send: 2_000,
    bonus_photo_send_only: 1_500,
    bonus_photographer: 2_000,
    bonus_photographer_priority_zero: 3_000,
    bonus_bus_guide: 600
  }.freeze

  def change
    add_column :guides, :pay_category, :string
    add_column :guides, :pay_level_two, :boolean, null: false, default: false

    create_table :drivers do |t|
      t.string :name, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    create_table :departures do |t|
      t.references :work_day, null: false, foreign_key: true
      t.string :label, null: false
      t.string :location, null: false
      t.datetime :starts_at, null: false
      t.string :status, null: false, default: "scheduled"
      t.datetime :closed_at
      t.timestamps
    end
    add_index :departures, [:work_day_id, :label], unique: true
    add_index :departures, :starts_at

    create_table :compensation_rates do |t|
      t.string :code, null: false
      t.integer :amount_cents, null: false
      t.datetime :effective_at, null: false
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :compensation_rates, [:code, :effective_at], unique: true
    add_check_constraint :compensation_rates, "amount_cents >= 0", name: "compensation_rate_nonnegative"

    create_table :compensation_assignments do |t|
      t.references :departure, null: false, foreign_key: true
      t.references :guide, foreign_key: true
      t.references :driver, foreign_key: true
      t.references :guide_day, foreign_key: true
      t.string :role_code, null: false
      t.string :photo_task, null: false, default: "none"
      t.boolean :also_drives, null: false, default: false
      t.boolean :bus_guide, null: false, default: false
      t.boolean :principal_photographer, null: false, default: false
      t.string :status, null: false, default: "planned"
      t.string :source, null: false, default: "manual"
      t.string :pay_category_snapshot
      t.boolean :pay_level_two_snapshot
      t.text :pricing_error
      t.datetime :priced_at
      t.references :updated_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_check_constraint :compensation_assignments,
      "(guide_id IS NOT NULL) <> (driver_id IS NOT NULL)",
      name: "one_compensation_person"
    add_index :compensation_assignments, [:departure_id, :guide_id],
      unique: true, where: "guide_id IS NOT NULL", name: "unique_departure_guide"
    add_index :compensation_assignments, [:departure_id, :driver_id],
      unique: true, where: "driver_id IS NOT NULL", name: "unique_departure_driver"
    add_index :compensation_assignments, :departure_id,
      unique: true, where: "photo_task IN ('take_and_send', 'send_only') AND status NOT IN ('canceled', 'no_show')",
      name: "one_photo_task_per_departure"
    add_index :compensation_assignments, :departure_id,
      unique: true, where: "principal_photographer = TRUE AND status NOT IN ('canceled', 'no_show')",
      name: "one_principal_photographer"

    create_table :compensation_lines do |t|
      t.references :compensation_assignment, null: false, foreign_key: true,
        index: { name: "index_compensation_lines_on_assignment" }
      t.references :compensation_rate, foreign_key: true
      t.string :code, null: false
      t.integer :rate_cents, null: false
      t.integer :amount_cents, null: false
      t.integer :discount_percent, null: false, default: 0
      t.datetime :applied_at, null: false
      t.jsonb :details, null: false, default: {}
      t.timestamps
    end
    add_index :compensation_lines, [:compensation_assignment_id, :code],
      unique: true, name: "one_line_per_compensation_code"

    create_table :compensation_settlements do |t|
      t.references :guide, foreign_key: true
      t.references :driver, foreign_key: true
      t.date :week_start, null: false
      t.date :week_end, null: false
      t.integer :amount_cents, null: false, default: 0
      t.datetime :closed_at
      t.datetime :paid_at
      t.references :paid_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_check_constraint :compensation_settlements,
      "(guide_id IS NOT NULL) <> (driver_id IS NOT NULL)",
      name: "one_settlement_person"
    add_index :compensation_settlements, [:guide_id, :week_start],
      unique: true, where: "guide_id IS NOT NULL", name: "unique_guide_week"
    add_index :compensation_settlements, [:driver_id, :week_start],
      unique: true, where: "driver_id IS NOT NULL", name: "unique_driver_week"

    create_table :compensation_settlement_items do |t|
      t.references :compensation_settlement, null: false, foreign_key: true,
        index: { name: "index_compensation_settlement_items_on_settlement" }
      t.references :compensation_assignment, null: false, foreign_key: true,
        index: { name: "index_compensation_settlement_items_on_assignment" }
      t.integer :amount_cents, null: false
      t.timestamps
    end
    add_index :compensation_settlement_items,
      [:compensation_settlement_id, :compensation_assignment_id],
      unique: true, name: "one_assignment_per_settlement"

    create_table :compensation_adjustments do |t|
      t.references :compensation_settlement, null: false, foreign_key: true,
        index: { name: "index_compensation_adjustments_on_settlement" }
      t.references :source_assignment, null: false,
        foreign_key: { to_table: :compensation_assignments },
        index: { name: "index_compensation_adjustments_on_source" }
      t.integer :amount_cents, null: false
      t.text :reason, null: false
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :compensation_adjustments,
      [:compensation_settlement_id, :source_assignment_id],
      unique: true, name: "one_compensation_adjustment_per_source_week"

    reversible do |direction|
      direction.up do
        INITIAL_RATES.each do |code, cents|
          execute <<~SQL
            INSERT INTO compensation_rates
              (code, amount_cents, effective_at, created_at, updated_at)
            VALUES
              ('#{code}', #{cents}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
          SQL
        end
      end
    end
  end
end
