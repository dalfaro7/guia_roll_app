module Whatsapp
  class RollMessageFormatter
    LOCATION_ORDER = ["Sara-3&4", "Balsa", "Privado", "PM"].freeze
    LOCATION_TITLES = {
      "Sara-3&4" => "🌊 SARA 3 & 4",
      "Balsa" => "🛶 BALSA",
      "Privado" => "🚐 PRIVATE",
      "PM" => "🌙 PM"
    }.freeze
    ROLE_LABELS = {
      "River Guide" => "River Guide",
      "Photographer" => "Photographer",
      "Safety Kayaker" => "Safety Kayaker"
    }.freeze
    SPECIAL_ROLE_ICONS = {
      "Photographer" => "📷",
      "Safety Kayaker" => "🛟"
    }.freeze
    WEEKDAYS = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze
    MONTHS = %w[January February March April May June July August September October November December].freeze

    def initialize(work_day)
      @work_day = work_day
    end

    # Meta no permite saltos de línea dentro de una variable de plantilla.
    # Un solo parámetro permite incluir cualquier cantidad de guías.
    def template_parameter
      sections = ["📅 #{formatted_date}"]
      sections.concat(location_sections)
      sections << "📌 ASSIGNED TASKS: #{assigned_tasks_summary}" if assigned_tasks.any?
      sections << "⏳ STANDBY: #{standby_summary}" if standby_guides.any?
      sanitize_parameter(sections.join(" | "))
    end

    private

    attr_reader :work_day

    def formatted_date
      date = work_day.date
      "#{WEEKDAYS[date.wday]}, #{MONTHS[date.month - 1]} #{date.day}, #{date.year}"
    end

    def location_sections
      grouped = worked_guides.group_by(&:location)
      ordered_locations = LOCATION_ORDER + (grouped.keys.compact - LOCATION_ORDER).sort

      ordered_locations.filter_map do |location|
        guide_days = grouped[location]
        next if guide_days.blank?

        title = LOCATION_TITLES.fetch(location, "📍 #{location.to_s.upcase}")
        entries = guide_days.each_with_index.map do |guide_day, index|
          format_worked_guide(guide_day, index + 1)
        end
        "#{title}: #{entries.join(" • ")}"
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

    def format_worked_guide(guide_day, position)
      primary_role = guide_day.role_primary.presence || "River Guide"
      prefix = SPECIAL_ROLE_ICONS.fetch(primary_role, "#{position}.")
      roles = [primary_role, guide_day.role_secondary].compact_blank.map do |role|
        ROLE_LABELS.fetch(role, role)
      end.join(" / ")

      "#{prefix} #{guide_day.guide.name.to_s.strip} — #{roles}"
    end

    def special_role?(role)
      SPECIAL_ROLE_ICONS.key?(role)
    end

    def assigned_tasks
      @assigned_tasks ||= work_day.guide_days
        .where(status: :assigned_task)
        .includes(:guide)
        .to_a
        .sort_by { |guide_day| [guide_day.guide.priority || 999, guide_day.guide.name.to_s] }
    end

    def assigned_tasks_summary
      assigned_tasks.map do |guide_day|
        note = guide_day.status_note.presence || "Assigned task"
        "#{guide_day.guide.name.to_s.strip} — #{note}"
      end.join(" • ")
    end

def standby_guides
  @standby_guides ||= work_day.standby_guides_for_published_roll
end

    def standby_summary
      standby_guides.map { |guide_day| guide_day.guide.name.to_s.strip }.join(" • ")
    end

    def sanitize_parameter(value)
      value.to_s.gsub(/[\r\n\t]+/, " ").gsub(/\s{2,}/, " ").strip
    end
  end
end
