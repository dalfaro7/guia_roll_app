class TransportCompany < ApplicationRecord
  has_many :buses, dependent: :restrict_with_error
  has_many :drivers, dependent: :restrict_with_error

  before_validation :normalize_name

  validates :name, presence: true, uniqueness: { case_sensitive: false }

  private

  def normalize_name
    self.name = name.to_s.strip
  end
end
