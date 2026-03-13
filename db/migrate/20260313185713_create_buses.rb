class CreateBuses < ActiveRecord::Migration[8.1]
  def change
    create_table :buses do |t|
      t.string :company
      t.integer :capacity
      t.string :plate
      t.string :alias
      t.string :phone

      t.timestamps
    end
  end
end
