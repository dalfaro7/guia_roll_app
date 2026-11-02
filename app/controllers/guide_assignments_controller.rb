class GuideAssignmentsController < ApplicationController

  def index

    @guides = Guide.active.order(:name)

    if params[:guide_id].present? && params[:date].present?

      guide = Guide.find(params[:guide_id])
      date = Date.parse(params[:date])

      work_day = WorkDay.find_by(date: date)

      if work_day
        @daily_assignment =
          work_day.guide_days
                  .includes(:guide)
                  .find_by(guide_id: guide.id)
      end

    end

    if params[:range_guide_id].present?
      if params[:start_date].blank? || params[:end_date].blank?
        @range_error = "Indica las fechas inicial y final."
      else
        begin
          start_date = Date.iso8601(params[:start_date])
          end_date = Date.iso8601(params[:end_date])

          if end_date < start_date
            @range_error = "La fecha final debe ser igual o posterior a la inicial."
          else
            guide = Guide.find(params[:range_guide_id])
            @range = start_date..end_date
            @range_assignments =
              GuideDay.joins(:work_day)
                      .where(guide: guide)
                      .where(work_days: { date: @range })
                      .includes(:work_day)
                      .order("work_days.date ASC")
          end
        rescue Date::Error
          @range_error = "Indica fechas válidas."
        end
      end
    end

  end

end