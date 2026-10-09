class WeatherReportsController < ApplicationController
  def index
    @weather_reports = WeatherReport.recent.limit(2)
  end
end
