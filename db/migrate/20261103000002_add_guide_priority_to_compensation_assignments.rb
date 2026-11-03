class AddGuidePriorityToCompensationAssignments < ActiveRecord::Migration[8.1]
  def change
    add_column :compensation_assignments, :guide_priority_snapshot, :integer

    create_table :compensation_discount_rules do |t|
      t.string :code, null: false
      t.integer :percent, null: false
      t.datetime :effective_at, null: false
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :compensation_discount_rules, [:code, :effective_at], unique: true
    add_check_constraint :compensation_discount_rules,
      "percent BETWEEN 0 AND 100", name: "compensation_discount_percent_range"

    reversible do |direction|
      direction.up do
        execute <<~SQL
          INSERT INTO compensation_rates
            (code, amount_cents, effective_at, created_at, updated_at)
          SELECT
            'bonus_photographer_priority_zero', 3000,
            CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
          WHERE NOT EXISTS (
            SELECT 1 FROM compensation_rates
            WHERE code = 'bonus_photographer_priority_zero'
          )
        SQL
        { second_sara: 20, second_other: 30 }.each do |code, percent|
          execute <<~SQL
            INSERT INTO compensation_discount_rules
              (code, percent, effective_at, created_at, updated_at)
            VALUES
              ('#{code}', #{percent}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
          SQL
        end
      end
    end
  end
end
