class AddNotesToOfficeDayCredits < ActiveRecord::Migration[8.1]
  def change
    add_column :office_day_credits, :notes, :text
  end
end
