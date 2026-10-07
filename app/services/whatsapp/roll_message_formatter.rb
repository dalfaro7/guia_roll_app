module Whatsapp
  class RollMessageFormatter
    LOCATION_ORDER = ["Sara-3&4", "Balsa", "Privado", "PM"].freeze
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
    # Cada elemento corresponde, en orden, a {{1}} ... {{7}}.
    def template_parameters
      [
        formatted_date,
        location_summary("Sara-3&4"),
        location_summary("Balsa"),
        location_summary("Privado"),
        location_summary("PM"),
        assigned_tasks_summary,
        standby_summary
      ].map { |value| sanitize_parameter(value) }
    end

    private

    attr_reader :work_day

    def formatted_date
      date = work_day.date
      "#{WEEKDAYS[date.wday]}, #{MONTHS[date.month - 1]} #{date.day}, #{date.year}"
    end

    def location_summary(location)
      guide_days = worked_guides.select { |guide_day| guide_day.location == location }
      return "None" if guide_days.empty?

      guide_days.each_with_index.map do |guide_day, index|
        format_worked_guide(guide_day, index + 1)
      end.join(" • ")
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
      return "None" if assigned_tasks.empty?

      assigned_tasks.map do |guide_day|
        note = guide_day.status_note.presence || "Assigned task"
        "#{guide_day.guide.name.to_s.strip} — #{note}"
      end.join(" • ")
    end

    def standby_guides
      @standby_guides ||= work_day.guide_days
        .where(status: :standby)
        .includes(:guide)
        .to_a
        .select { |guide_day| guide_day.guide.active? }
        .sort_by { |guide_day| [guide_day.guide.priority || 999, guide_day.guide.name.to_s] }
    end

    def standby_summary
      return "None" if standby_guides.empty?

      standby_guides.map { |guide_day| guide_day.guide.name.to_s.strip }.join(" • ")
    end

    def sanitize_parameter(value)
      value.to_s.gsub(/[\r\n\t]+/, " ").gsub(/\s{2,}/, " ").strip.presence || "None"
    end
  end
end
