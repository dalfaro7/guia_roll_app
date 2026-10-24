require 'test_helper'
class KayaktalkieSpeedAlertTest < ActiveSupport::TestCase
  setup do
    @account = KayaktalkieAccount.create!(name: 'Speed sources', phone: '89990666', password: 'Test-speed-123456', location_enabled: true)
    @time = Time.current
  end
  test 'sources preserve separate peaks after acknowledging and closing episodes' do
    KayaktalkieSpeedAlert.record!(@account, @time, 100)
    KayaktalkieSpeedAlert.record!(@account, @time, 95, source: 'estimated')
    gps = @account.kayaktalkie_speed_alerts.find_by!(source: 'gps')
    estimate = @account.kayaktalkie_speed_alerts.find_by!(source: 'estimated')
    gps.update!(acknowledged_at: @time)
    KayaktalkieSpeedAlert.record!(@account, @time+30, 120)
    KayaktalkieSpeedAlert.record!(@account, @time+30, 110, source: 'estimated')
    KayaktalkieSpeedAlert.record!(@account, @time+60, 92)
    KayaktalkieSpeedAlert.record!(@account, @time+60, 90, source: 'estimated')
    KayaktalkieSpeedAlert.record!(@account, @time+90, nil)
    assert_equal 120, gps.reload.peak_kmh
    assert_equal 110, estimate.reload.peak_kmh
    assert gps.acknowledged_at
    assert gps.ended_at
    assert estimate.ended_at
    assert_equal 2, @account.kayaktalkie_speed_alerts.count
  end
  test 'fresh averages persist but retained averages never open a new episode' do
    start = 6.minutes.ago
    (0..10).each do |i|
      KayaktalkieTrackingIngest.call(@account, {'latitude'=>0.0,'longitude'=>i*0.01,'accuracy'=>5.0,'capturedAt'=>(start+i*30).to_f*1000})
    end
    alert = @account.kayaktalkie_speed_alerts.find_by!(source: 'estimated')
    assert_operator alert.peak_kmh, :>, 90
    assert_equal 0, @account.kayaktalkie_speed_alerts.where(source: 'gps').count
    [330,350].each do |t|
      KayaktalkieTrackingIngest.call(@account, {'latitude'=>0.0,'longitude'=>0.1,'accuracy'=>100.0,'capturedAt'=>(start+t).to_f*1000})
    end
    assert_equal 1, @account.kayaktalkie_speed_alerts.count
    assert alert.reload.ended_at
    assert_in_delta (start+300).to_f, alert.last_at.to_f, 0.001
    assert KayaktalkiePosition.find_by!(kayaktalkie_account:@account).speed_estimate['last_valid']
  end
end
