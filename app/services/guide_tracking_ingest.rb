class GuideTrackingIngest
  class InvalidPosition < StandardError; end
  def self.call(guide, data)
    values = %w[latitude longitude accuracy capturedAt].map { |key| data[key] }
    speed = data['speedMps']
    valid_number = ->(v) { v.is_a?(Numeric) && v.finite? }
    raise InvalidPosition unless values.all?(&valid_number)
    latitude, longitude, accuracy, captured = values
    raise InvalidPosition unless latitude.abs <= 90 && longitude.abs <= 180 && accuracy >= 0 && captured.between?(24.hours.ago.to_f * 1000, 1.minute.from_now.to_f * 1000)
    raise InvalidPosition unless speed.nil? || (valid_number.call(speed) && speed >= 0 && (speed * 3.6).finite?)
    time = Time.at(captured / 1000.0)
    guide.with_lock do
      position = GuidePosition.find_or_initialize_by(guide: guide)
      return false if position.persisted? && time <= position.captured_at
      kmh = speed && speed * 3.6
      GuideSpeedAlert.record!(guide, time, kmh)
      position.update!(latitude: latitude, longitude: longitude, accuracy: accuracy, captured_at: time, received_at: Time.current, speed_kmh: kmh)
    end
    true
  end
end
