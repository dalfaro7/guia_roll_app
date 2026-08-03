class CreateOfficeVacationCredits < ActiveRecord::Migration[8.1]
  def change
    create_table :office_vacation_credits do |t|
      t.references :office_employee,
                   null: false,
                   foreign_key: true

      t.date :date, null: false

      t.string :source,
               null: false,
               default: "legacy"

      t.boolean :used,
                null: false,
                default: false

      t.date :used_on

      t.text :notes

      t.timestamps
    end

    add_index :office_vacation_credits,
              [:office_employee_id, :used]

    add_index :office_vacation_credits,
              [:office_employee_id, :date, :source],
              unique: true,
              name: "idx_office_vacation_credits_unique"
  end
end
