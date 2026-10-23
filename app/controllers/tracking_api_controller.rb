class TrackingApiController < ActionController::API
  include ActionController::Cookies
  include ActionController::RequestForgeryProtection
  before_action :authenticate_mobile!, only: [:location, :logout, :account]
  before_action :authenticate_admin!, only: [:users, :alerts, :ack, :report, :me, :map_voice]
  rate_limit to: 15, within: 15.minutes, only: :login, with: -> { render json: { error: 'Demasiados intentos. Espera 15 minutos.' }, status: :too_many_requests }
  def login
    account = MobileAccount.includes(:guide).find_by(phone: MobileAccount.normalize_phone(params[:phone].presence || params[:email]))
    unless account&.available? && account.valid_password?(params[:password])
      return render json: { error: 'Credenciales incorrectas.' }, status: :unauthorized
    end
    render json: { token: MobileSession.issue!(account), user: account.client_profile }
  end
  def account
    render json: { user: @mobile_session.mobile_account.client_profile }
  end
  def logout
    @mobile_session.destroy!
    render json: { ok: true }
  end
  def location
    unless @mobile_session.mobile_account.can_share_location?
      return render json: { error: 'Esta cuenta solo tiene acceso a voz.' }, status: :forbidden
    end
    GuideTrackingIngest.call(@mobile_session.mobile_account.guide, params)
    render json: { ok: true }
  rescue GuideTrackingIngest::InvalidPosition
    render json: { error: 'Coordenadas, fecha o velocidad inválidas.' }, status: :bad_request
  end
  def me
    render json: { id: @admin.id, name: @admin.name, role: 'admin' }
  end
  def map_voice
    floors = VoiceFloor.where(room_key: VoiceChannel.enabled.select(:room_key)).where('expires_at > ?', Time.current).where.not(holder_identity: nil)
    response.headers['Cache-Control'] = 'no-store'
    render json: { speakers: floors.map { |floor| { identity: floor.holder_identity, expiresAt: (floor.expires_at.to_f * 1000).round } } }
  end
  def users
    positions = GuidePosition.all.index_by(&:guide_id)
    render json: MobileAccount.includes(:guide, :mobile_sessions).where(active: true, account_type: 'guide', location_enabled: true).map { |account|
      g = account.guide; p = positions[g.id]
      { id: g.id, name: g.name, voice_identities: account.mobile_sessions.select { |mobile| mobile.expires_at > Time.current }.map { |mobile| "mobile-#{mobile.id}" }, phone: account.phone, latitude: p&.latitude, longitude: p&.longitude, accuracy: p&.accuracy, speed_kmh: p&.speed_kmh, captured_at: millis(p&.captured_at), received_at: millis(p&.received_at) }
    }
  end
  def alerts
    unread = GuideSpeedAlert.where(acknowledged_at: nil)
    render json: { limitKmh: 90, unreadCount: unread.count, items: unread.order(first_at: :desc, id: :desc).limit(100).map { |a| serialize(a) } }
  end
  def ack
    return head :forbidden unless valid_browser_csrf?
    alert = GuideSpeedAlert.find_by(id: params[:id])
    return render json: { error: 'Alerta no encontrada.' }, status: :not_found unless alert
    alert.with_lock { alert.update!(acknowledged_at: alert.acknowledged_at || Time.current) }
    render json: { ok: true }
  end
  def report
    day = params[:date].presence || Time.current.in_time_zone('America/Costa_Rica').to_date.iso8601
    raise ArgumentError unless day.match?(/\A\d{4}-\d{2}-\d{2}\z/)
    date = Date.iso8601(day)
    render json: { day: date, timezone: 'America/Costa_Rica', limitKmh: 90, items: GuideSpeedAlert.where(day: date).order(first_at: :desc, id: :desc).map { |a| serialize(a) } }
  rescue Date::Error, ArgumentError
    render json: { error: 'Fecha inválida.' }, status: :bad_request
  end
  private
  def authenticate_mobile!
    @mobile_session = MobileSession.authenticate(request.authorization.to_s.delete_prefix('Bearer '))
    render json: { error: 'Inicia sesión.' }, status: :unauthorized unless @mobile_session
  end
  def authenticate_admin!
    @admin = request.env['warden']&.user
    return render json: { error: 'Inicia sesión.' }, status: :unauthorized unless @admin
    render json: { error: 'Solo administradores.' }, status: :forbidden unless @admin.admin?
  end
  def valid_browser_csrf?
    request.headers['X-CSRF-Token'].present? && valid_authenticity_token?(session, request.headers['X-CSRF-Token'])
  end
  def millis(time) = time && (time.to_f * 1000).round
  def serialize(a)
    { id: a.id, user_id: a.guide_id, user_name: a.guide_name, day: a.day, first_at: millis(a.first_at), last_at: millis(a.last_at), peak_kmh: a.peak_kmh, ended_at: millis(a.ended_at), acknowledged_at: millis(a.acknowledged_at) }
  end
end
