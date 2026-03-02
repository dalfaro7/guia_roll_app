class CreateMonthlyBalances < ActiveRecord::Migration[8.1]
  def change
    create_table :monthly_balances do |t|
      t.references :guide, null: false, foreign_key: true
      t.date :month
      t.integer :worked_days
      t.integer :balance
      t.integer :bus_days

      t.timestamps
    end
  end
end
