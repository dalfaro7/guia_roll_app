class DayOffReportController < ApplicationController

  def index
    if params[:month].present?
      year, month = params[:month].split("-").map(&:to_i)
      @month = Date.new(year, month, 1)
    else
      @month = Date.today.beginning_of_month
    end

    start_date = @month.beginning_of_month
    end_date   = @month.end_of_month

    @calendar_days = (start_date..end_date).to_a

    @guides = Guide.where(priority: 1).order(:name)

    @work_days =
      WorkDay.where(date: start_date..end_date)

    @guide_days =
      GuideDay.joins(:work_day)
              .where(work_days: { date: start_date..end_date })

    @manual_day_offs =
      ManualDayOff.where(date: start_date..end_date)
  end



  def assign_week_day_off

    start_date = Date.parse(params[:week_start])
    end_date   = start_date + 6.days

    guides = Guide.where(id: params[:guide_ids])

    assigned_count = 0
    skipped_count  = 0

    guides.each do |guide|

      (start_date..end_date).each do |date|

        work_day = WorkDay.find_by(date: date)

        if work_day && (work_day.generated? || work_day.published?)
          skipped_count += 1
          next
        end

        ManualDayOff.find_or_create_by!(
          guide: guide,
          date: date
        )

        assigned_count += 1

      end

    end

    redirect_to day_off_report_path(month: start_date.strftime("%Y-%m")),
                notice: "#{assigned_count} day off assigned. #{skipped_count} skipped because roll was generated or published."

  end

end