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
  end_date = start_date + 6.days

  guides = Guide.where(id: params[:guide_ids])

  work_days = WorkDay.where(date: start_date..end_date)

  assigned_count = 0
  skipped_count = 0

  guides.each do |guide|

    work_days.each do |work_day|

      # REGLA: bloquear si el roll ya fue generado o publicado
      if work_day.generated? || work_day.published?
        skipped_count += 1
        next
      end

      guide_day = work_day.guide_days.find_by(guide: guide)
      next unless guide_day

      next unless guide_day.standby? || guide_day.worked?

      guide_day.update!(
        status: :day_off,
        manually_modified: true
      )

      assigned_count += 1

    end

  end

  redirect_to day_off_report_path(month: start_date.strftime("%Y-%m")),
              alert: "#{assigned_count} day off assigned. #{skipped_count} skipped because roll was generated or published."

end

end