module OfficeDays
  class CreditAssignmentService
    class NoAvailableCreditError < StandardError; end
    class InvalidCreditTypeError < StandardError; end

    CREDIT_TYPES = {
      day: {
        association: :office_day_credit,
        credits: :office_day_credits,
        day_off_source: "credit"
      },
      vacation: {
        association: :office_vacation_credit,
        credits: :office_vacation_credits,
        day_off_source: nil
      }
    }.freeze

    def initialize(employee_day:, credit_type:, use_credit:)
      @employee_day = employee_day
      @credit_type = credit_type.to_sym
      @use_credit =
        ActiveModel::Type::Boolean.new.cast(use_credit)

      validate_credit_type!
    end

    def call
      if should_use_credit?
        assign_or_update_credit
      else
        release_credit
      end
    end

    private

    def validate_credit_type!
      return if CREDIT_TYPES.key?(@credit_type)

      raise InvalidCreditTypeError,
            "Tipo de crédito no válido: #{@credit_type}"
    end

    def configuration
      CREDIT_TYPES.fetch(@credit_type)
    end

    def should_use_credit?
      @use_credit && correct_status?
    end

    def correct_status?
      case @credit_type
      when :day
        @employee_day.day_off?
      when :vacation
        @employee_day.vacation?
      else
        false
      end
    end

    def assign_or_update_credit
      credit = associated_credit

      if credit.present? &&
         credit.office_employee_id == @employee_day.office_employee_id

        credit.mark_as_used!(
          used_on: @employee_day.date
        )

        apply_day_off_source
        return
      end

      release_credit if credit.present?
      assign_new_credit
    end

    def assign_new_credit
      credit = next_available_credit

      unless credit
        raise NoAvailableCreditError,
              no_available_credit_message
      end

      credit.mark_as_used!(
        used_on: @employee_day.date
      )

      attributes = {
        configuration[:association] => credit
      }

      if configuration[:day_off_source].present?
        attributes[:day_off_source] =
          configuration[:day_off_source]
      end

      @employee_day.update!(attributes)
    end

    def release_credit
      credit = associated_credit
      return unless credit

      credit.release!

      attributes = {
        configuration[:association] => nil
      }

      if @credit_type == :day
        attributes[:day_off_source] =
          @employee_day.day_off? ? "manual" : nil
      end

      @employee_day.update!(attributes)
    end

    def next_available_credit
      available_credits
        .lock
        .first
    end

    def associated_credit
      @employee_day.public_send(
        configuration[:association]
      )
    end

    def available_credits
      @employee_day
        .office_employee
        .public_send(configuration[:credits])
        .available
    end

    def apply_day_off_source
      return unless @credit_type == :day

      @employee_day.update!(
        day_off_source: "credit"
      )
    end

    def no_available_credit_message
      case @credit_type
      when :day
        "El oficinista no tiene días acumulados disponibles."
      when :vacation
        "El oficinista no tiene días de vacaciones disponibles."
      end
    end
  end
end