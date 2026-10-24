require 'test_helper'
class KayaktalkieSpeedWindowTest < ActiveSupport::TestCase
  def point(t, lon=0, lat=0, accuracy=5)
    {'t'=>t.to_f, 'lat'=>lat.to_f, 'lon'=>lon.to_f, 'accuracy'=>accuracy}
  end
  def window(points)
    history=[]; result=nil
    points.each { |p| history,result=KayaktalkieSpeedWindow.call(history,p) }
    [history,result]
  end
  test 'haversine reference and stationary window' do
    assert_in_delta 111195.08, KayaktalkieSpeedWindow.distance(point(0),point(0,1)), 0.1
    _,r=window((0..10).map { |i| point(i*30) })
    assert_equal 'ready',r[:status]; assert_equal 0,r[:kmh]
  end
  test 'thirty and sixty second samples yield same straight line estimate' do
    [30,60].each do |interval|
      _,r=window((0..300).step(interval).map { |t| point(t,t*0.00001) })
      assert_equal 'ready',r[:status]
      assert_in_delta 4.003, r[:kmh],0.001
      assert_equal 300/interval+1,r[:samples]
    end
  end
  test 'return trip combines zero endpoints with positive path at equal weight' do
    _,r=window((0..10).map { |i| point(i*30,(i<=5 ? i : 10-i)*0.001) })
    assert_in_delta 0,r[:endpoints_kmh],0.0001
    assert_in_delta r[:segments_kmh]/2,r[:kmh],0.0001
  end
  test 'irregular captures use exact window and elapsed time' do
    history,r=window([0,40,90,150,210,260,310].map { |t| point(t,t*0.00001) })
    assert_in_delta 4.003,r[:kmh],0.001
    assert_equal 300,r[:window_seconds]
    assert_equal 0,history.first['t']
  end
  test 'warmup gaps and poor precision do not fabricate speed' do
    h,r=window([point(0),point(30)])
    assert_equal 'warming_up',r[:status]
    h,r=KayaktalkieSpeedWindow.call(h,point(200))
    assert_equal 1,h.size
    h,r=KayaktalkieSpeedWindow.call(h,point(230,0,0,100))
    assert_empty h; assert_equal 'poor_accuracy',r[:status]
  end
  test 'history remains bounded' do
    h,r=window((0..100).map { |i| point(i*30,i*0.001) })
    assert_equal 11,h.size; assert_equal 'ready',r[:status]
  end
  test 'last valid estimate survives warmup and poor accuracy for at most five minutes' do
    h, ready = window((0..10).map { |i| point(i*30) })
    assert_equal 300000, ready[:calculated_at]
    h, pending = KayaktalkieSpeedWindow.call(h, point(330,0,0,100), ready)
    assert_equal 0, pending[:last_valid]['kmh']
    h, pending = KayaktalkieSpeedWindow.call(h, point(360), pending)
    assert_equal 300000, pending[:last_valid]['calculated_at']
    _, expired = KayaktalkieSpeedWindow.call(h, point(601), pending)
    assert_nil expired[:last_valid]
  end

end
