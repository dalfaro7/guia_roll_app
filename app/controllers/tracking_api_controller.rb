class TrackingApiController < ActionController::API
  include ActionController::Cookies
  include ActionController::RequestForgeryProtection
  include KayaktalkieAuthentication
  before_action :authenticate_kayaktalkie!, except: :login
  before_action :require_kayaktalkie_map!, only: [:users, :me, :map_voice, :map_area, :operators]
  before_action :require_kayaktalkie_admin!, only: [:alerts, :ack, :report]
  before_action :check_kayak_csrf!, only: [:location, :location_batch, :logout, :map_area]
  rate_limit to: 15, within: 15.minutes, only: :login, with: -> { render json: { error: 'Demasiados intentos. Espera 15 minutos.' }, status: :too_many_requests }
  def login
    account = KayaktalkieAccount.find_by(phone: KayaktalkieAccount.normalize_phone(params[:phone].presence || params[:email]))
    unless account&.available? && account.valid_password?(params[:password])
      return render json: { error: 'Credenciales incorrectas.' }, status: :unauthorized
    end
    render json: { token: KayaktalkieSession.issue!(account), user: account.client_profile }
  end
  def account
    render json: { user: @kayaktalkie_session.kayaktalkie_account.client_profile }
  end
  def logout
    @kayaktalkie_session.destroy!
    render json: { ok: true }
  end
  def location
    unless @kayaktalkie_session.kayaktalkie_account.can_share_location?
      return render json: { error: 'Esta cuenta solo tiene acceso a voz.' }, status: :forbidden
    end
    KayaktalkieTrackingIngest.call(@account, params)
    render json: { ok: true }
  rescue KayaktalkieTrackingIngest::InvalidPosition
    render json: { error: 'Coordenadas, fecha o velocidad inválidas.' }, status: :bad_request
  end
  def location_batch
    return render json: {error:'Sin permiso de ubicación.'}, status: :forbidden unless @account.can_share_location?
    samples=params[:samples]
    raise KayaktalkieTrackingIngest::InvalidPosition unless samples.is_a?(Array) && samples.size.between?(1,60)
    rows=samples.map do |sample|
      raise KayaktalkieTrackingIngest::InvalidPosition unless sample.is_a?(ActionController::Parameters)
      sample.permit(:latitude,:longitude,:accuracy,:capturedAt,:speedMps).to_h
    end
    accepted=KayaktalkieTrackingIngest.batch(@account,rows)
    render json: {ok:true,accepted:accepted}
  rescue KayaktalkieTrackingIngest::InvalidPosition
    render json: {error:'Lote de ubicaciones inválido.'}, status: :bad_request
  end
  def me
    render json: @account.client_profile
  end
  def map_area
    area = params.require(:area).permit(:lat, :lng, :zoom).to_h
    limits = { 'lat' => -85.051129..85.051129, 'lng' => -180..180, 'zoom' => 0..19 }
    unless limits.all? { |key, range| area[key].is_a?(Numeric) && area[key].finite? && range.cover?(area[key]) }
      return render json: { error: 'Área inválida.' }, status: :unprocessable_entity
    end
    @account.with_lock do
      # An old browser preference must never overwrite an existing server preference.
      @account.update!(map_area: area) unless params[:import] == true && @account.map_area.present?
    end
    render json: { area: @account.map_area }
  end
  def map_voice
    channels = @account.allowed_channels
    if params.key?(:channel_id)
      return render json: {speakers: []} if params[:channel_id].blank?
      channel = channels.find_by(id: params[:channel_id])
      return head :forbidden unless channel
      channels = channels.where(id: channel.id)
    end
    floors = VoiceFloor.where(room_key: channels.select(:room_key)).where('expires_at > ?', Time.current).where.not(holder_identity: nil)
    response.headers['Cache-Control'] = 'no-store'
    render json: { speakers: floors.map { |floor| { identity: floor.holder_identity, expiresAt: (floor.expires_at.to_f * 1000).round } } }
  end
  def operators
    response.headers['Cache-Control'] = 'no-store'
    return render json: [] if params[:channel_id].blank?
    channel = @account.allowed_channels.find_by(id: params[:channel_id])
    return head :forbidden unless channel
    accounts = KayaktalkieAccount.where(active: true, role: 'operator')
      .where(id: channel.voice_memberships.select(:kayaktalkie_account_id))
      .where(id: KayaktalkieTeamMembership.where(kayaktalkie_team_id: channel.kayaktalkie_team_id).select(:kayaktalkie_account_id))
    render json: accounts.includes(:kayaktalkie_sessions).map { |account|
      {id: account.id, name: account.name, identities: account.kayaktalkie_sessions.select { |s| s.expires_at.future? }.map { |s| "mobile-#{s.id}" }}
    }
  end
  def users
    response.headers['Cache-Control'] = 'no-store'
    memberships = KayaktalkieTeamMembership.all
    memberships = memberships.where(kayaktalkie_team_id: @account.kayaktalkie_team_ids) unless @account.admin?
    # Unassigned accounts remain manageable, but are not part of the operational map.
    visible = KayaktalkieAccount.where(id: memberships.select(:kayaktalkie_account_id))
    if params.key?(:channel_id)
      channel = @account.allowed_channels.find_by(id: params[:channel_id])
      return render json: [] if params[:channel_id].blank?
      return head :forbidden unless channel
      visible = visible.where(id: channel.voice_memberships.select(:kayaktalkie_account_id)).where(id: KayaktalkieTeamMembership.where(kayaktalkie_team_id: channel.kayaktalkie_team_id).select(:kayaktalkie_account_id))
    end
    positions = KayaktalkiePosition.where(kayaktalkie_account_id: visible.select(:id)).index_by(&:kayaktalkie_account_id)
    render json: visible.includes(:kayaktalkie_sessions).where(active: true, location_enabled: true).map { |account|
      p = positions[account.id]
      p = nil if p && !@account.admin? && (p.team_ids_at_capture & @account.kayaktalkie_team_ids).empty?
      { id: account.id, name: account.name, voice_identities: account.kayaktalkie_sessions.select { |mobile| mobile.expires_at > Time.current }.map { |mobile| "mobile-#{mobile.id}" }, latitude: p&.latitude, longitude: p&.longitude, accuracy: p&.accuracy, speed_kmh: p&.speed_kmh, speed_estimate: p&.speed_estimate, captured_at: millis(p&.captured_at), received_at: millis(p&.received_at) }
    }
  end

  def alerts
    unread = KayaktalkieSpeedAlert.where(acknowledged_at: nil)
    render json: { limitKmh: 90, unreadCount: unread.count, items: unread.order(first_at: :desc, id: :desc).limit(100).map { |a| serialize(a) } }
  end
  def ack
    return head :forbidden unless valid_browser_csrf?
    alert = KayaktalkieSpeedAlert.find_by(id: params[:id])
    return render json: { error: 'Alerta no encontrada.' }, status: :not_found unless alert
    alert.with_lock { alert.update!(acknowledged_at: alert.acknowledged_at || Time.current) }
    render json: { ok: true }
  end
  def report
    day = params[:date].presence || Time.current.in_time_zone('America/Costa_Rica').to_date.iso8601
    raise ArgumentError unless day.match?(/\A\d{4}-\d{2}-\d{2}\z/)
    date = Date.iso8601(day)
    render json: { day: date, timezone: 'America/Costa_Rica', limitKmh: 90, items: KayaktalkieSpeedAlert.where(day: date).order(first_at: :desc, id: :desc).map { |a| serialize(a) } }
  rescue Date::Error, ArgumentError
    render json: { error: 'Fecha inválida.' }, status: :bad_request
  end
  private
  def check_kayak_csrf!
    head :forbidden if @browser && !valid_browser_csrf?
  end
  def valid_browser_csrf?
    request.headers['X-CSRF-Token'].present? && valid_authenticity_token?(session, request.headers['X-CSRF-Token'])
  end
  def millis(time) = time && (time.to_f * 1000).round
  def serialize(a)
    { id: a.id, user_id: a.kayaktalkie_account_id, user_name: a.account_name, day: a.day, first_at: millis(a.first_at), last_at: millis(a.last_at), peak_kmh: a.peak_kmh, source: a.source, ended_at: millis(a.ended_at), acknowledged_at: millis(a.acknowledged_at) }
  end
end
