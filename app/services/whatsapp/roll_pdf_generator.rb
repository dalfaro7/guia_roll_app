require "prawn"

module Whatsapp
  class RollPdfGenerator
    PAGE_MARGIN = 40
    ROW_MINIMUM_SPACE = 42

    def initialize(work_day)
      @formatter = RollDocumentFormatter.new(work_day)
    end

    def render
      document = Prawn::Document.new(
        page_size: "A4",
        margin: PAGE_MARGIN,
        info: { Title: "Arenal Rafting Company - Guide Schedule" }
      )
      draw_page_header(document)
      formatter.sections.each { |section| draw_section(document, section) }
      document.render
    end

    private

    attr_reader :formatter

    def draw_page_header(document, continued: false)
      document.fill_color "17324D"
      document.text "ARENAL RAFTING COMPANY", size: 18, style: :bold
      document.text continued ? "GUIDE SCHEDULE - CONTINUED" : "GUIDE SCHEDULE", size: 14, style: :bold
      document.fill_color "4A5568"
      document.move_down 4
      document.text safe_text(formatter.date_label), size: 11
      document.move_down 14
    end

    def draw_section(document, section)
      ensure_space(document, 56)
      document.fill_color "0B7A53"
      document.text safe_text(section[:title]), size: 12, style: :bold
      document.stroke_color "9FB5C8"
      document.move_down 3
      document.stroke_horizontal_rule
      document.move_down 5

      section[:rows].each { |row| draw_row(document, row, section[:title]) }
      document.move_down 10
    end

    def draw_row(document, row, section_title)
      ensure_space(document, ROW_MINIMUM_SPACE, continuation_title: section_title)
      document.fill_color "17324D"
      document.text(
        format("%02d  %s", row[:position], safe_text(row[:name])),
        size: 10,
        style: :bold
      )
      document.fill_color "4A5568"
      document.indent(27) { document.text safe_text(row[:details]), size: 9 }
      document.stroke_color "D7E0E8"
      document.move_down 4
      document.stroke_horizontal_rule
      document.move_down 5
    end

    def ensure_space(document, required_space, continuation_title: nil)
      return if document.cursor >= required_space

      document.start_new_page
      draw_page_header(document, continued: true)
      draw_continuation_title(document, continuation_title) if continuation_title
    end

    def draw_continuation_title(document, title)
      document.fill_color "0B7A53"
      document.text "#{safe_text(title)} - CONTINUED", size: 12, style: :bold
      document.stroke_color "9FB5C8"
      document.move_down 3
      document.stroke_horizontal_rule
      document.move_down 5
    end

    def safe_text(value)
      I18n.transliterate(value.to_s).encode("US-ASCII", invalid: :replace, undef: :replace, replace: "?")
    end
  end
end
