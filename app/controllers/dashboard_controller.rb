class DashboardController < ApplicationController
  def index
    if params[:month].present?
      begin
        year, month = params[:month].split("-").map(&:to_i)
        @month = Date.new(year, month, 1)
      rescue
        @month = Date.today.beginning_of_month
      end
    else
      @month = Date.today.beginning_of_month
    end

    month_range = @month.beginning_of_month..@month.end_of_month
    @selected_special_role = params[:special_role].presence || "all"
    assigned_statuses = [:worked, :assigned_task]

    @guides = Guide.active.order(:name)

    assigned_days_by_guide_id = GuideDay
      .joins(:work_day)
      .where(guide: @guides, status: assigned_statuses)
      .where(work_days: { date: month_range })
      .group(:guide_id)
      .count

    @assigned_work_slots = @guides.sum do |guide|
      assigned_days_by_guide_id[guide.id].to_i
    end

    @worked_month_days = GuideDay
      .joins(:work_day)
      .where(status: assigned_statuses)
      .where(work_days: { date: month_range })
      .distinct
      .count("work_days.date")

    @average =
      if @guides.any?
        (@assigned_work_slots.to_f / @guides.size).round
      else
        0
      end

    @dashboard_data = @guides.map do |guide|
      worked = assigned_days_by_guide_id[guide.id].to_i

      percentage =
        @assigned_work_slots > 0 ? (worked.to_f / @assigned_work_slots * 100).round(2) : 0

      deviation = worked - @average

      {
        guide: guide,
        worked: worked,
        percentage: percentage,
        deviation: deviation
      }
    end.sort_by { |data| [-data[:worked], data[:guide].name] }

    @chart_data = @dashboard_data.map do |data|
      [data[:guide].name, data[:worked]]
    end

    @selected_guide =
      if params[:guide_id].present?
        @guides.find { |g| g.id == params[:guide_id].to_i } || @guides.first
      else
        @guides.first
      end

    @historical_data =
      if @selected_guide.present?
        GuideDay
          .joins(:work_day)
          .where(guide: @selected_guide, status: assigned_statuses)
          .group(Arel.sql("DATE_TRUNC('month', work_days.date)"))
          .order(Arel.sql("DATE_TRUNC('month', work_days.date)"))
          .count
          .map do |month_date, assigned_days|
            [
              month_date.strftime("%Y-%m"),
              assigned_days.to_i
            ]
          end
      else
        []
      end


      special_role_rows = GuideDay
  .joins(:work_day, :guide)
  .where(work_days: { date: month_range })
  .where(status: :worked)
  .where(
    "guide_days.role_primary IN (?) OR guide_days.role_secondary IN (?)",
    ["Safety Kayaker", "Photographer"],
    ["Bus Guide", "Bus Guide & SendPhotos"]
  )
  .select(
    "guides.id AS guide_id",
    "guides.name AS guide_name",
    "guide_days.role_primary",
    "guide_days.role_secondary"
  )

special_role_counts = Hash.new do |hash, guide_name|
  hash[guide_name] = {
    guide_name: guide_name,
    safety_kayaker: 0,
    photographer: 0,
    bus_guide: 0,
    total: 0
  }
end

special_role_rows.each do |row|
  guide_name = row.guide_name
  data = special_role_counts[guide_name]

  if row.role_primary == "Safety Kayaker"
    data[:safety_kayaker] += 1
    data[:total] += 1
  end

  if row.role_primary == "Photographer"
    data[:photographer] += 1
    data[:total] += 1
  end

  if ["Bus Guide", "Bus Guide & SendPhotos"].include?(row.role_secondary)
    data[:bus_guide] += 1
    data[:total] += 1
  end
end

@special_role_data = special_role_counts.values.sort_by { |data| -data[:total] }
@filtered_special_role_data =
  case @selected_special_role
  when "safety_kayaker"
    @special_role_data.select { |data| data[:safety_kayaker].to_i > 0 }
  when "photographer"
    @special_role_data.select { |data| data[:photographer].to_i > 0 }
  when "bus_guide"
    @special_role_data.select { |data| data[:bus_guide].to_i > 0 }
  else
    @special_role_data
  end

@special_role_chart_data = @special_role_data.map do |data|
  {
    name: data[:guide_name],
    "Safety Kayaker": data[:safety_kayaker],
    "Photographer": data[:photographer],
    "Bus Guide": data[:bus_guide]
  }
end

  end
end