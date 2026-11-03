module Compensation
  class ScheduleSync
    def self.backfill_future!(now: Time.current)
      return unless CompensationRate.table_exists?

      first_rate = CompensationRate.minimum(:effective_at)
      return unless first_rate

      local_now = now.in_time_zone("America/Costa_Rica")
      earliest_date = [first_rate.in_time_zone("America/Costa_Rica").to_date,
        local_now.hour < 6 ? local_now.to_date : local_now.to_date + 1.day].max
      linked_ids = CompensationAssignment.where.not(guide_day_id: nil)
        .select(:guide_day_id)
      GuideDay.joins(:work_day)
        .where(work_days: { date: earliest_date.. })
        .where(status: [:worked, :assigned_task])
        .where.not(id: linked_ids)
        .includes(:guide, :work_day)
        .find_each do |guide_day|
          next if guide_day.assigned_task? &&
            !guide_day.status_note.to_s.strip.casecmp?("Host")

          call(guide_day)
        end
    end

    def self.call(guide_day)
      new(guide_day).call
    end

    def initialize(guide_day)
      @guide_day = guide_day
      @work_day = guide_day.work_day
    end

    def call
      return unless CompensationRate.table_exists?

      started_on = CompensationRate.minimum(:effective_at)
        &.in_time_zone("America/Costa_Rica")&.to_date
      return if started_on.blank? || @work_day.date < started_on

      assignment = CompensationAssignment.find_by(guide_day: @guide_day)
      if assignment&.source == "manual"
        if !@guide_day.worked? &&
            !(@guide_day.assigned_task? && @guide_day.status_note.to_s.strip.casecmp?("Host")) &&
            !%w[canceled no_show].include?(assignment.status)
          assignment.update!(status: "canceled")
          Compensation::RepriceDay.call(@work_day, guide: @guide_day.guide)
          promote_principal_photographer(assignment.departure)
        end
        return
      end
      role = inferred_role

      unless role
        if assignment
          departure = assignment.departure
          remove_automatic_assignment(assignment)
          promote_principal_photographer(departure)
        end
        return
      end

      departure = find_or_create_departure
      values = {
        departure: departure,
        guide: @guide_day.guide,
        role_code: role,
        status: departure.closed? ? "performed" : "planned",
        photo_task: photo_task(role),
        also_drives: @guide_day.role_secondary == "Driver",
        bus_guide: @guide_day.role_secondary.to_s.include?("Bus Guide"),
        principal_photographer: role == "photographer" &&
          !departure.compensation_assignments.active.where(role_code: "photographer", principal_photographer: true).where.not(id: assignment&.id).exists?
      }

      if assignment
        assignment.update!(values)
      else
        assignment = CompensationAssignment.create!(
          values.merge(guide_day: @guide_day, source: "automatic")
        )
      end

      promote_principal_photographer(departure)
      Compensation::RepriceDay.call(departure.work_day, guide: @guide_day.guide)
    end

    private

    def inferred_role
      if @guide_day.worked?
        case @guide_day.role_primary
        when "Photographer" then "photographer"
        when "Safety Kayaker" then "safety_kayak"
        else
          if @guide_day.role_secondary == "Head Guide"
            @guide_day.location.to_s.start_with?("Sara") ? "hg_sara" : "hg_balsa"
          else
            "river_guide"
          end
        end
      elsif @guide_day.assigned_task? && @guide_day.status_note.to_s.strip.casecmp?("Host")
        "host"
      end
    end

    def photo_task(role)
      return "none" if role == "photographer"

      @guide_day.role_secondary.to_s.include?("SendPhotos") ? "send_only" : "none"
    end

    def find_or_create_departure
      location = @guide_day.location.presence || "Balsa"
      @work_day.departures.find_or_create_by!(label: location) do |departure|
        departure.location = location
        departure.starts_at = Time.find_zone!("America/Costa_Rica").local(
          @work_day.date.year, @work_day.date.month, @work_day.date.day, 6
        )
      end
    end

    def remove_automatic_assignment(assignment)
      assignment.update!(status: "canceled")
      Compensation::RepriceDay.call(@work_day, guide: @guide_day.guide)
    end

    def promote_principal_photographer(departure)
      photographers = departure.compensation_assignments.active
        .where(role_code: "photographer")
      return if !photographers.exists? ||
        photographers.where(principal_photographer: true).exists?

      photographers.order(:id).first.update!(principal_photographer: true)
    end
  end
end
