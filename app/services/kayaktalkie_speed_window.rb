# Five-minute displacement estimate, not instantaneous speed.
class KayaktalkieSpeedWindow
  WINDOW = 300.0
  MAX_GAP = 120.0
  MAX_ACCURACY = 50.0
  def self.distance(a, b)
    rad = Math::PI / 180
    lat1, lat2 = a['lat'] * rad, b['lat'] * rad
    h = Math.sin((lat2-lat1)/2)**2 + Math.cos(lat1)*Math.cos(lat2)*Math.sin((b['lon']-a['lon'])*rad/2)**2
    6_371_008.8 * 2 * Math.asin(Math.sqrt(h.clamp(0, 1)))
  end
  def self.call(samples, point)
    return [[], {status: 'poor_accuracy'}] if point['accuracy'] > MAX_ACCURACY
    samples = samples.select { |p| p['t'] < point['t'] }
    samples = [] if samples.any? && point['t'] - samples.last['t'] > MAX_GAP
    points = samples + [point]
    cutoff = point['t'] - WINDOW
    # Keep the boundary anchor, at most five minutes plus one capture interval.
    anchor = points.rindex { |p| p['t'] <= cutoff }
    points = points.drop(anchor) if anchor
    points = points.last(64)
    return [points, {status: 'warming_up', samples: points.size}] if points.first['t'] > cutoff
    return [[point], {status: 'warming_up', samples: 1}] if points.each_cons(2).any? { |a,b| b['t']-a['t'] > MAX_GAP }
    window = points.map(&:dup)
    if window.first['t'] < cutoff
      a,b = window[0],window[1]
      fraction = (cutoff-a['t'])/(b['t']-a['t'])
      # Interpolate only the boundary segment; handle longitude wrap.
      delta = (b['lon']-a['lon']+180)%360-180
      window[0] = {'t'=>cutoff, 'lat'=>a['lat']+(b['lat']-a['lat'])*fraction,
                   'lon'=>(a['lon']+delta*fraction+180)%360-180}
    end
    direct = distance(window.first, window.last)
    path = window.each_cons(2).sum { |a,b| distance(a,b) }
    # Sum(distance)/sum(time) is the duration-weighted mean of segment speeds.
    endpoints = direct/WINDOW*3.6
    segments = path/WINDOW*3.6
    [points, {status: 'ready', kmh: (endpoints+segments)/2,
              endpoints_kmh: endpoints, segments_kmh: segments,
              window_seconds: WINDOW.to_i, samples: points.size}]
  end
end
