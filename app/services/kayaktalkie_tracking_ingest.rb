class KayaktalkieTrackingIngest
  class InvalidPosition < StandardError; end
  def self.call(account, data)
    values = %w[latitude longitude accuracy capturedAt].map { |key| data[key] }
    speed = data['speedMps']
    valid_number = ->(v) { v.is_a?(Numeric) && v.finite? }
    raise InvalidPosition unless values.all?(&valid_number)
    latitude, longitude, accuracy, captured = values
    raise InvalidPosition unless latitude.abs <= 90 && longitude.abs <= 180 && accuracy >= 0 && captured.between?(24.hours.ago.to_f * 1000, 1.minute.from_now.to_f * 1000)
    raise InvalidPosition unless speed.nil? || (valid_number.call(speed) && speed >= 0 && (speed * 3.6).finite?)
    time = Time.at(captured / 1000.0)
    account.with_lock do
      position = KayaktalkiePosition.find_or_initialize_by(kayaktalkie_account: account)
      return false if position.persisted? && time <= position.captured_at
      history = position.speed_samples
      previous = position.speed_estimate || {}
      if previous['status'] == 'ready' && !previous['calculated_at'] && position.captured_at
        previous = previous.merge('calculated_at' => position.captured_at.to_f * 1000)
      end
      previous = {} if position.team_ids_at_capture.sort != account.kayaktalkie_team_ids.sort
      history = [] if position.team_ids_at_capture.sort != account.kayaktalkie_team_ids.sort
      samples, estimate = KayaktalkieSpeedWindow.call(history, {'t'=>time.to_f, 'lat'=>latitude, 'lon'=>longitude, 'accuracy'=>accuracy}, previous)
      kmh = speed && speed * 3.6
      KayaktalkieSpeedAlert.record!(account, time, kmh, source: 'gps')
      # Only a fresh complete window is a new measurement, never the retained display value.
      estimated_kmh = estimate[:status] == 'ready' ? estimate[:kmh] : nil
      KayaktalkieSpeedAlert.record!(account, time, estimated_kmh, source: 'estimated')
      position.update!(speed_samples: samples, speed_estimate: estimate, team_ids_at_capture: account.kayaktalkie_team_ids, latitude: latitude, longitude: longitude, accuracy: accuracy, captured_at: time, received_at: Time.current, speed_kmh: kmh)
    end
    true
  end
end
