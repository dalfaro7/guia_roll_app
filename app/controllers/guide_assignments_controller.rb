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

    if params[:week_guide_id].present?

      guide = Guide.find(params[:week_guide_id])

      start_week =
        if params[:week_start].present?
          Date.parse(params[:week_start])
        else
          Date.today.beginning_of_week
        end

      end_week = start_week + 6.days

      @weekly_assignments =
        GuideDay.joins(:work_day)
                .where(guide: guide)
                .where(work_days: { date: start_week..end_week })
                .includes(:work_day)
                .order("work_days.date ASC")

      @week_range = start_week..end_week

    end

  end

end