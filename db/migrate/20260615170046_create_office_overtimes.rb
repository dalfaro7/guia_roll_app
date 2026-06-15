class CreateOfficeOvertimes < ActiveRecord::Migration[8.1]
  def change
    create_table :office_overtimes do |t|
      t.references :office_employee, null: false, foreign_key: true
      t.date :date
      t.decimal :hours
      t.string :reason
      t.boolean :approved, default: true, null: false

      t.timestamps
    end
  end
end
