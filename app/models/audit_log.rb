class AuditLog < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :work_day, optional: true

  validates :action, presence: true
  validates :auditable_type, presence: true

  scope :recent, -> { order(created_at: :desc) }
end