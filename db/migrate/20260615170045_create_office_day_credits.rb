class CreateOfficeDayCredits < ActiveRecord::Migration[8.1]
  def change
    create_table :office_day_credits do |t|
      t.references :office_employee, null: false, foreign_key: true
      t.date :date
      t.string :source
      t.boolean :used, default: false, null: false
      t.date :used_on

      t.timestamps
    end
  end
end
