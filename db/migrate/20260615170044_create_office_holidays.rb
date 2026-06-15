class CreateOfficeHolidays < ActiveRecord::Migration[8.1]
  def change
    create_table :office_holidays do |t|
      t.date :date
      t.string :name
      t.boolean :double_pay, default: true, null: false

      t.timestamps
    end
  end
end
