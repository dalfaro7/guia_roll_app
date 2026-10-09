require "uri"

class WeatherReport < ApplicationRecord
  scope :recent, -> { order(reported_at: :desc, id: :desc) }

  validates :source_uid,
            presence: true,
            uniqueness: true,
            length: { maximum: 255 }
  validates :title,
            presence: true,
            length: { maximum: 255 }
  validates :body,
            presence: true,
            length: { maximum: 100_000 }
  validates :reported_at, :source_name, :source_url, presence: true
  validate :source_url_must_be_a_chatgpt_share

  private

  def source_url_must_be_a_chatgpt_share
    uri = URI.parse(source_url.to_s)
    trusted = uri.scheme == "https" &&
      uri.host == "chatgpt.com" &&
      uri.path.start_with?("/share/")

    errors.add(:source_url, "must be a ChatGPT shared conversation") unless trusted
  rescue URI::InvalidURIError
    errors.add(:source_url, "must be a valid URL")
  end
end
