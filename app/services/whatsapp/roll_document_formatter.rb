module Whatsapp
  class RollDocumentFormatter
    LOCATION_ORDER = ["Sara-3&4", "Balsa", "Privado", "PM"].freeze
    LOCATION_TITLES = {
      "Sara-3&4" => "SARA 3 & 4",
      "Balsa" => "BALSA",
      "Privado" => "PRIVATE",
      "PM" => "PM"
    }.freeze
    WEEKDAYS = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze
    MONTHS = %w[January February March April May June July August September October November December].freeze

    def initialize(work_day)
      @work_day = work_day
    end

    def date_label
      date = work_day.date
      "#{WEEKDAYS[date.wday]}, #{MONTHS[date.month - 1]} #{date.day}, #{date.year}"
    end

    def sections
      location_sections.tap do |result|
        result << section("ASSIGNED TASKS", assigned_task_rows) if assigned_tasks.any?
        result << section("STANDBY", standby_rows) if standby_guides.any?
      end
    end

    private

    attr_reader :work_day

    def location_sections
      grouped = worked_guides.group_by(&:location)
      ordered_locations = LOCATION_ORDER + (grouped.keys.compact - LOCATION_ORDER).sort

      ordered_locations.filter_map do |location|
        guide_days = grouped[location]
        next if guide_days.blank?

        rows = guide_days.each_with_index.map do |guide_day, index|
          {
            position: index + 1,
            name: guide_day.guide.name.to_s.strip,
            details: roles_for(guide_day)
          }
        end
        section(LOCATION_TITLES.fetch(location, location.to_s.upcase), rows)
      end
    end

    def worked_guides
      @worked_guides ||= work_day.guide_days
        .where(status: :worked)
        .includes(:guide)
        .to_a
        .sort_by do |guide_day|
          [
            LOCATION_ORDER.index(guide_day.location) || 99,
            special_role?(guide_day.role_primary) ? 1 : 0,
            guide_day.guide.priority || 999,
            guide_day.guide.name.to_s
          ]
        end
    end

    def roles_for(guide_day)
      [guide_day.role_primary.presence || "River Guide", guide_day.role_secondary]
        .compact_blank
        .join(" / ")
    end

    def special_role?(role)
      ["Photographer", "Safety Kayaker"].include?(role)
    end

    def assigned_tasks
      @assigned_tasks ||= work_day.guide_days
        .where(status: :assigned_task)
        .includes(:guide)
        .to_a
        .sort_by { |guide_day| [guide_day.guide.priority || 999, guide_day.guide.name.to_s] }
    end

    def assigned_task_rows
      assigned_tasks.each_with_index.map do |guide_day, index|
        {
          position: index + 1,
          name: guide_day.guide.name.to_s.strip,
          details: guide_day.status_note.presence || "Assigned task"
        }
      end
    end

def standby_guides
  @standby_guides ||= work_day.standby_guides_for_published_roll
end

    def standby_rows
      standby_guides.each_with_index.map do |guide_day, index|
        {
          position: index + 1,
          name: guide_day.guide.name.to_s.strip,
          details: "Available"
        }
      end
    end

    def section(title, rows)
      { title: title, rows: rows }
    end
  end
end
