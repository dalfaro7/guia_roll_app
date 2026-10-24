class VoiceController < ActionController::API
  include ActionController::Cookies
  include ActionController::RequestForgeryProtection
  include KayaktalkieAuthentication
  before_action :authenticate_kayaktalkie!
  before_action :authenticate_participant!
  before_action :browser_csrf!, except: [:status, :channels]
  before_action :authorize_channel!, except: :channels
  rescue_from VoiceTransport::Unavailable, with: ->(e) { render json: { error: e.message }, status: :service_unavailable }
  def channels
    response.headers['Cache-Control'] = 'no-store'
    render json: { channels: available_channels.map(&:client_profile) }
  end
  def join
    response.headers['Cache-Control'] = 'no-store'
    render json: { serverUrl: VoiceTransport.url, participantToken: VoiceTransport.token(@identity, @name, room: @channel.room_key), room: @channel.room_key, identity: @identity, maxSeconds: VoiceFloor::MAX_SECONDS }
  end
  def status
    floor = VoiceFloor.for_channel(@channel)
    render json: { configured: VoiceTransport.configured?, speaker: floor.holder_identity && floor.expires_at&.future? && { identity: floor.holder_identity, name: floor.holder_name, expiresAt: (floor.expires_at.to_f * 1000).round } }
  end
  def claim
    render json: VoiceTurn.claim(@identity, @name, channel: @channel)
  rescue VoiceTurn::Occupied
    render json: { error: 'Otro participante tiene el turno.' }, status: :conflict
  end
  def release
    render json: { ok: VoiceTurn.release(@identity, params[:lease].to_s, channel: @channel) }
  end
  private
  def available_channels
    @account.allowed_channels
  end
  def authorize_channel!
    # Legacy APKs use the former general room only when assigned to that account.
    @channel = if params[:channel_id].present?
      available_channels.find_by(id: params[:channel_id])
    else
      available_channels.find_by(room_key: VoiceFloor::ROOM)
    end
    render json: { error: 'No tienes acceso a este canal.' }, status: :forbidden unless @channel
  end
  def authenticate_participant!
    @identity = "mobile-#{@kayaktalkie_session.id}"
    @name = @account.name
  end
  def browser_csrf!
    if @browser && !valid_authenticity_token?(session, request.headers['X-CSRF-Token'])
      head :forbidden
    end
  end
end
