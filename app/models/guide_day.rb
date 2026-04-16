class GuideDay < ApplicationRecord
  belongs_to :guide
  belongs_to :work_day
  belongs_to :modified_by, class_name: "User", optional: true

  enum :status, {
    worked: 0,
    standby: 1,
    day_off: 2,
    vacation: 3,
    penalized: 4,
    assigned_task: 5
  }

  validates :status, presence: true
  validates :status_note, presence: true, if: :requires_status_note?

  before_validation :clear_status_note_unless_needed
  before_save :apply_day_off_balance, if: :will_save_change_to_status?

  scope :available_for_date, ->(date) {
    where(status: :standby)
      .where.not(
        guide_id: ManualDayOff.where(date: date).select(:guide_id)
      )
  }

  scope :counts_as_worked_for_roll, -> {
    where(status: [:worked, :penalized])
  }

  scope :ordered_for_display, -> {
    joins(:guide).order(
      Arel.sql("
        CASE guide_days.status
          WHEN 0 THEN 1
          WHEN 4 THEN 2
          WHEN 1 THEN 3
          WHEN 5 THEN 4
          ELSE 5
        END
      "),
      Arel.sql("
        CASE guide_days.location
          WHEN 'Sara-3&4' THEN 1
          WHEN 'Balsa' THEN 2
          WHEN 'Privado' THEN 3
          WHEN 'PM' THEN 4
          ELSE 5
        END
      "),
      "guides.priority ASC"
    )
  }

  def counts_as_worked_for_roll?
    worked? || penalized?
  end

  def counts_as_standby_for_roll?
    standby? || assigned_task?
  end

  def unavailable_for_assignment?
    day_off? || vacation? || assigned_task? || penalized? || worked?
  end

  def payable_day?
    worked?
  end

  def unpaid_day?
    penalized?
  end

  def requires_status_note?
    penalized? || assigned_task?
  end

  def location_css_class
    case location
    when "Sara-3&4"
      "location-sara"
    when "Balsa"
      "location-balsa"
    when "PM"
      "location-pm"
    when "Privado"
      "location-privado"
    else
      ""
    end
  end

  private

  def clear_status_note_unless_needed
    self.status_note = nil unless requires_status_note?
  end

  def apply_day_off_balance
    old_status = status_before_last_save || status_was
    new_status = status

    return unless new_status == "day_off"
    return if old_status == "day_off"
    return if day_off_consumed

    guide.consume_day_off!
    self.day_off_consumed = true
  end
end