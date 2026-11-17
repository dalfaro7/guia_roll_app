require "uri"

class WeatherReport < ApplicationRecord
  IMN_SOURCE_URLS = %w[
    https://www.imn.ac.cr/especial/tablas/balsa.html
    https://www.imn.ac.cr/especial/tablas/vblanca.html
  ].freeze

  scope :recent, -> { order(reported_at: :desc, id: :desc) }

  validates :source_uid, presence: true, uniqueness: true,
                         length: { maximum: 255 }
  validates :title, presence: true, length: { maximum: 255 }
  validates :body, presence: true, length: { maximum: 100_000 }
  validates :reported_at, :source_name, :source_url, presence: true
  validate :source_url_must_be_trusted

  private

  def source_url_must_be_trusted
    value = source_url.to_s
    uri = URI.parse(value)

    legacy_source = uri.scheme == "https" &&
      uri.host == "chatgpt.com" && uri.port == 443 &&
      uri.userinfo.nil? && uri.path.start_with?("/share/")

    return if IMN_SOURCE_URLS.include?(value) || legacy_source

    errors.add(:source_url, "must be an approved IMN table or a ChatGPT shared conversation")
  rescue URI::InvalidURIError
    errors.add(:source_url, "must be a valid URL")
  end
end
