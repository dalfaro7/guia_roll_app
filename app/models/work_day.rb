class WorkDay < ApplicationRecord
  has_many :work_day_versions, dependent: :destroy
  has_many :guide_days, dependent: :destroy
  has_many :guides, through: :guide_days
  has_many :location_slots, dependent: :destroy
  has_many :bus_assignments, dependent: :destroy
  has_many :audit_logs, dependent: :nullify

  accepts_nested_attributes_for :guide_days, update_only: true
  after_create :initialize_guide_days

  validates :date, presence: true
  validates :guides_requested,
            numericality: { greater_than_or_equal_to: 0 },
            allow_nil: true
  validate :date_cannot_be_in_the_past

  enum :status, {
    draft: 0,
    generated: 1,
    published: 2
  }

  def buses_for(location)
    bus_assignments.includes(:bus).where(location: location)
  end

  def passengers_for(location)
    location_slots.find_by(location: location)&.passengers.to_i
  end

  def bus_capacity_for(location)
    buses_for(location).joins(:bus).sum("buses.capacity")
  end

  def seats_remaining_for(location)
    bus_capacity_for(location) - passengers_for(location)
  end

  def initialize_guide_days
    Guide.active.find_each do |guide|
      guide_days.create!(
        guide: guide,
        status: :standby
      )
    end
  end

  def generate_roles!
    raise "WorkDay must be draft" unless draft?

    RoleGeneratorV2.new(self).generate!
    log_event("generate_roles", "draft", "generated")
  end

  def calculated_guides_requested
    location_slots.count
  end

  def assigned_roll_count
  guide_days.where(status: :worked).count
  end

  def required_roll_count
    location_slots.count
  end

  def publish!
    raise "Only generated days can be published" unless generated?

    previous_status = status

    update!(
      status: :published,
      published_at: Time.current
    )

    log_event("publish", previous_status, "published")
  end

  def unpublish!
    raise "Only published days can be unpublished" unless published?

    previous_status = status

    ActiveRecord::Base.transaction do
      RoleResetService.new(self).revert_only_balances
      update!(status: :generated, published_at: nil)
      log_event("unpublish", previous_status, "generated")
    end
  end

  def reset_roll!
    raise "Cannot reset draft day" if draft?

    RoleResetService.new(self).call
  end

  def regenerate_with_new_count!(new_count)
    raise "Cannot regenerate draft days" if draft?

    new_count = new_count.to_i
    previous_status = status
    previous_count  = guides_requested

    if new_count != location_slots.count
      raise ArgumentError, "new_count must match location_slots.count"
    end

    ActiveRecord::Base.transaction do
      RoleResetService.new(self).call

      update!(guides_requested: new_count)

      log_event(
        "regenerate_with_new_count",
        previous_status,
        "draft",
        previous_count,
        new_count
      )

      generate_roles!
    end
  end

  private

  def log_event(event, previous_status, new_status, previous_count = nil, new_count = nil)
    WorkDayVersion.create!(
      work_day: self,
      snapshot: {
        event: event,
        previous_status: previous_status,
        new_status: new_status,
        previous_guides_requested: previous_count,
        new_guides_requested: new_count,
        performed_at: Time.current
      }
    )
  end

  def date_cannot_be_in_the_past
    return if date.blank?
    errors.add(:date, "cannot be in the past") if date < Date.today
  end



  def force_delete!
  ActiveRecord::Base.transaction do

    RoleResetService.new(self).call rescue nil

    work_day_versions.delete_all
    guide_days.delete_all
    location_slots.delete_all

    AuditLog.where(work_day_id: id).delete_all

    destroy!
  end
end
end