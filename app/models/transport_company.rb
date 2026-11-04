class TransportCompany < ApplicationRecord
  has_many :buses, dependent: :restrict_with_error
  has_many :drivers, dependent: :restrict_with_error
  has_many :transport_rates, dependent: :restrict_with_error

  after_create :create_default_transport_rates

  before_validation :normalize_name

  validates :name, presence: true, uniqueness: { case_sensitive: false }

  private

  def create_default_transport_rates
    TransportRate::LOCATIONS.product(TransportRate::CATEGORIES).each do |location, category|
      transport_rates.create!(location: location, size_category: category,
        amount_cents: 12_000)
    end
  end

  def normalize_name
    self.name = name.to_s.strip
  end
end
