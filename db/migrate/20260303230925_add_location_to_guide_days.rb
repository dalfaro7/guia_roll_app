class AddLocationToGuideDays < ActiveRecord::Migration[8.1]
  def change
    add_column :guide_days, :location, :string, default: "Balsa"
  end
end
