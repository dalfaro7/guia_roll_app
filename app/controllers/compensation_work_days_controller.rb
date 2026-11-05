class CompensationWorkDaysController < ApplicationController
  before_action :require_compensation_view!

  def show
    @work_day = WorkDay.find(params[:work_day_id])
    @departures = @work_day.departures.chronological
      .includes(compensation_assignments: [:guide, :driver, :compensation_lines]).to_a
    @departures.sort_by! do |departure|
      section_position = Departure::OPERATING_SECTIONS.values.index do |locations|
        locations.include?(departure.location)
      end || Departure::OPERATING_SECTIONS.size
      [section_position, departure.starts_at, departure.id]
    end
    @operating_sections = Departure::OPERATING_SECTIONS.map do |location, locations|
      [location, @departures.select { |departure| locations.include?(departure.location) }]
    end
    @can_edit = Compensation::EditWindow.allowed?(
      user: current_user, work_day: @work_day
    )
  end
end
