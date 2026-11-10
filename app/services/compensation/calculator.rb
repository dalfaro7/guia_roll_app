module Compensation
  class Calculator
    class MissingRate < StandardError; end
    class MissingProfile < StandardError; end

    def self.call(assignment)
      new(assignment).call
    end

    def initialize(assignment)
      @assignment = assignment
      @departure = assignment.departure
    end

    def call
      CompensationAssignment.transaction do
        @assignment.lock!
        existing = @assignment.compensation_lines.index_by(&:code)
        lines = payable? ? calculated_lines(existing) : []

        @assignment.compensation_lines.delete_all
        lines.each { |attrs| @assignment.compensation_lines.create!(attrs) }
        @assignment.update_columns(
          pricing_error: nil,
          priced_at: Time.current,
          pay_category_snapshot: category,
          guide_priority_snapshot: guide_priority
        )
      end

      @assignment.reload
    rescue MissingRate, MissingProfile => error
      @assignment.compensation_lines.delete_all
      @assignment.update_columns(pricing_error: error.message, priced_at: nil)
      @assignment.reload
    end

    private

    def payable?
      @departure.status != "canceled" &&
        !%w[canceled no_show].include?(@assignment.status)
    end

    def category
      return nil unless @assignment.guide?

      if @departure.started? && @assignment.pay_category_snapshot.present?
        @assignment.pay_category_snapshot
      else
        @assignment.guide.pay_category
      end
    end

    def salaried?
      category == "salaried"
    end

    def guide_priority
      return nil unless @assignment.guide?

      if @departure.started? && !@assignment.guide_priority_snapshot.nil?
        @assignment.guide_priority_snapshot
      else
        @assignment.guide.priority
      end
    end

    def calculated_lines(existing)
      result = []
      base = main_code
      result << line_for(base, existing, main: true) if base

      if @assignment.role_code == "photographer"
        photo_code = guide_priority == 0 ?
          "bonus_photographer_priority_zero" : "bonus_photographer"
        result << line_for(photo_code, existing)
      elsif !head_role?
        result << line_for("bonus_guide_drives", existing) if @assignment.also_drives?
        case @assignment.photo_task
        when "take_and_send"
          result << line_for("bonus_photo_take_and_send", existing)
        when "send_only"
          result << line_for("bonus_photo_send_only", existing)
        end
        if @assignment.bus_guide? && salaried? &&
            (@assignment.photo_task == "none" || guide_priority.to_i >= 2)
          result << line_for("bonus_bus_guide", existing)
        end
      end

      result
    end

    def head_role?
      %w[tl_balsa tl_sara hg_balsa hg_sara].include?(@assignment.role_code)
    end

    def main_code
      if @assignment.driver?
        return nil if %w[driver_hg driver_la_fortuna].include?(@assignment.role_code) &&
          second_departure?
        return @assignment.role_code
      end
      raise MissingProfile, "Falta la categoría económica de #{@assignment.guide.name}" if category.blank?

      case @assignment.role_code
      when "river_guide"
        return nil if salaried?

        {
          "freelance_apprentice" => "guide_apprentice",
          "freelance_regular" => "guide_regular",
          "freelance_invoice" => "guide_invoice"
        }.fetch(category)
      when "photographer", "safety_kayak"
        salaried? ? nil : @assignment.role_code
      when "tl_balsa", "tl_sara", "hg_balsa", "hg_sara"
        salaried? ? nil : @assignment.role_code
      end
    end

    def second_departure?
      return false if @assignment.role_code == "host"

      scope = CompensationAssignment
        .joins(:departure)
        .where(departures: { work_day_id: @departure.work_day_id })
        .where(guide_id: @assignment.guide_id, driver_id: @assignment.driver_id)
        .where.not(role_code: "host")
        .active
        .order("departures.starts_at ASC, departures.id ASC, compensation_assignments.id ASC")

      scope.pluck(:id).index(@assignment.id).to_i.positive?
    end

    def line_for(code, existing, main: false)
      previous = existing[code]
      rate = CompensationRate.for(code, at: @departure.starts_at)
      raise MissingRate, "No hay tarifa vigente para #{code}" unless rate

      applied_rate = if @departure.started? && previous
        previous.rate_cents
      else
        rate.amount_cents
      end
      discount = if main && second_departure?
        @departure.started? && previous ? previous.discount_percent : second_departure_discount
      else
        0
      end
      amount = (applied_rate * (100 - discount) + 50) / 100

      {
        compensation_rate: rate,
        code: code,
        rate_cents: applied_rate,
        amount_cents: amount,
        discount_percent: discount,
        applied_at: @departure.starts_at,
        details: {
          role_code: @assignment.role_code,
          pay_category: category,
          guide_priority: guide_priority,
          departure_label: @departure.label,
          location: @departure.location
        }
      }
    end

    def second_departure_discount
      transport_second_trip = @assignment.role_code == "driver_per_trip" &&
        @assignment.bus_assignment&.location == "PM" &&
        BusAssignment.where(work_day_id: @departure.work_day_id,
          bus_id: @assignment.bus_assignment.bus_id,
          driver_id: @assignment.driver_id,
          location: "Sara-3&4", outing_variant: "Sara-4").exists?
      sara_to_pm = @assignment.guide? && @departure.location == "PM" &&
        CompensationAssignment.joins(:departure)
          .where(guide_id: @assignment.guide_id,
            departures: { work_day_id: @departure.work_day_id,
              location: %w[Sara-3&4 Sara-3 Sara-4] })
          .active
          .where.not(departures: { status: "canceled" })
          .where("departures.starts_at < ?", @departure.starts_at)
          .exists?
      return 0 unless @departure.location.to_s.start_with?("Sara") ||
        sara_to_pm || transport_second_trip

      rule = CompensationDiscountRule.for("second_sara", at: @departure.starts_at)
      raise MissingRate, "No hay descuento vigente para second_sara" unless rule

      rule.percent
    end
  end
end
