class CreateOfficeEmployees < ActiveRecord::Migration[8.1]
  def change
    create_table :office_employees do |t|
      t.string :name
      t.boolean :active, default: true, null: false

      t.timestamps
    end
  end
end
