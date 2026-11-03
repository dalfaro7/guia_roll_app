class CreateTransportRates < ActiveRecord::Migration[8.1]
  def up
    create_table :transport_rates do |t|
      t.string :location, null: false
      t.string :size_category, null: false
      t.integer :amount_cents, null: false, default: 12_000
      t.timestamps
    end
    add_index :transport_rates, [:location, :size_category], unique: true
    add_check_constraint :transport_rates, "amount_cents >= 0",
      name: "transport_rate_amount_nonnegative"

    execute <<~SQL
      INSERT INTO transport_rates (location, size_category, amount_cents, created_at, updated_at)
      VALUES
        ('Balsa', 'small', 12000, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
        ('Balsa', 'large', 12000, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
        ('Sara-3&4', 'small', 12000, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
        ('Sara-3&4', 'large', 12000, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
        ('PM', 'small', 12000, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
        ('PM', 'large', 12000, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
        ('Privado', 'small', 12000, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
        ('Privado', 'large', 12000, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    SQL
  end

  def down
    drop_table :transport_rates
  end
end
