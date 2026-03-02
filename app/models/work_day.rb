class WorkDay < ApplicationRecord

  # ==============================
  # RELATIONS
  # ==============================
  has_many :work_day_versions, dependent: :destroy
  has_many :guide_days, dependent: :destroy
  has_many :guides, through: :guide_days

  accepts_nested_attributes_for :guide_days, update_only: true
  after_create :initialize_guide_days

  # ==============================
  # VALIDATIONS
  # ==============================
  validates :date, presence: true
  validates :guides_requested, presence: true
  validate :date_cannot_be_in_the_past

  # ==============================
  # ENUM
  # ==============================
  enum :status, {
    draft: 0,
    generated: 1,
    published: 2
  }


  # ==============================
  # inicializar guide_day
  # ==============================
  def initialize_guide_days
  Guide.active.find_each do |guide|
    guide_days.create!(
      guide: guide,
      status: :standby
    )
  end
end

  # ==============================
  # GENERATE ROLES
  # ==============================
  def generate_roles!
    raise "WorkDay must be draft" unless draft?

    RoleGenerator.new(self).call
    log_event("generate_roles", "draft", "generated")
  end

  # ==============================
  # PUBLISH
  # ==============================
  def publish!
    raise "Only generated days can be published" unless generated?

    previous_status = status

    update!(
      status: :published,
      published_at: Time.current
    )

    log_event("publish", previous_status, "published")
  end

  # ==============================
  # UNPUBLISH
  # ==============================
  def unpublish!
    raise "Only published days can be unpublished" unless published?

    previous_status = status

    ActiveRecord::Base.transaction do
      revert_balances
      update!(status: :generated, published_at: nil)
      log_event("unpublish", previous_status, "generated")
    end
  end


  # ==============================
  # RESET ROLL
  # ==============================
  def reset_roll!
    raise "Cannot reset draft day" if draft?

    previous_status = status

    ActiveRecord::Base.transaction do
      revert_balances if published?

      guide_days.destroy_all

      update!(
        status: :draft,
        published_at: nil
      )

      log_event("reset_roll", previous_status, "draft")
    end
  end


  # ==============================
  # REGENERATE WITH NEW COUNT
  # ==============================
  def regenerate_with_new_count!(new_count)
    raise "Cannot regenerate draft days" if draft?

    previous_status = status
    previous_count  = guides_requested

    ActiveRecord::Base.transaction do

      # Si estaba publicado → revertir balances
      revert_balances if published?

      # Borrar asignaciones anteriores
      guide_days.destroy_all

      # Volver a draft con nuevo número
      update!(
        status: :draft,
        guides_requested: new_count,
        published_at: nil
      )

      log_event(
        "regenerate_with_new_count",
        previous_status,
        "draft",
        previous_count,
        new_count
      )

      # Generar nuevo roll
      generate_roles!
    end
  end

  private

  # ==============================
  # AUDIT LOG
  # ==============================
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

  # ==============================
  # BALANCE REVERSION
  # ==============================
  def revert_balances
    guide_days.worked.includes(:guide).each do |gd|
      month = date.beginning_of_month

      balance = MonthlyBalance.find_by(
        guide: gd.guide,
        month: month
      )

      next unless balance

      balance.update!(
        worked_days: [balance.worked_days - 1, 0].max
      )

      gd.guide.update!(
        total_worked_days: [gd.guide.total_worked_days - 1, 0].max
      )
    end
  end

  # ==============================
  # VALIDATION
  # ==============================
  def date_cannot_be_in_the_past
    return if date.blank?
    errors.add(:date, "cannot be in the past") if date < Date.today
  end
end