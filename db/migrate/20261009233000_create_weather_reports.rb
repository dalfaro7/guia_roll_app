class CreateWeatherReports < ActiveRecord::Migration[8.0]
  def change
    create_table :weather_reports do |t|
      t.string :source_uid, null: false
      t.string :title, null: false
      t.text :body, null: false
      t.datetime :reported_at, null: false
      t.string :source_name, null: false, default: "ChatGPT"
      t.string :source_url, null: false

      t.timestamps
    end

    add_index :weather_reports, :source_uid, unique: true
    add_index :weather_reports, :reported_at
  end
end
