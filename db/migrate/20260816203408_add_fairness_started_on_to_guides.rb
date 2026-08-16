class AddFairnessStartedOnToGuides < ActiveRecord::Migration[8.1]
  def change
    add_column :guides, :fairness_started_on, :date
  end
end
