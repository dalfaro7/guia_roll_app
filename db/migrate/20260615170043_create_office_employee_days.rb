class CreateOfficeEmployeeDays < ActiveRecord::Migration[8.1]
  def change
    create_table :office_employee_days do |t|
      t.references :office_employee, null: false, foreign_key: true
      t.date :date
      t.integer :status
      t.boolean :holiday_paid, default: false, null: false
      t.string :day_off_source
      t.text :notes

      t.timestamps
    end
  end
end
