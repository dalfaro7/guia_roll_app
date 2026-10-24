class KayaktalkiePushController < ActionController::API
  include ActionController::Cookies
  include KayaktalkieAuthentication
  before_action :authenticate_kayaktalkie!
  def update
    return head :forbidden if @browser
    token=params[:token].to_s
    unless token.match?(/\A(?:ExponentPushToken|ExpoPushToken)\[[a-zA-Z0-9_-]{10,200}\]\z/)
      return render json: {error:'Token de notificaciones inválido.'}, status: :unprocessable_entity
    end
    KayaktalkieSession.transaction do
      KayaktalkieSession.where(expo_push_token:token).where.not(id:@kayaktalkie_session.id).update_all(expo_push_token:nil)
      @kayaktalkie_session.update!(expo_push_token:token)
    end
    render json: {ok:true,enabled:KayaktalkiePushGateway.enabled?}
  rescue ActiveRecord::RecordNotUnique
    render json: {error:'Reintenta registrar las notificaciones.'}, status: :conflict
  end
  def destroy
    return head :forbidden if @browser
    @kayaktalkie_session.update!(expo_push_token:nil)
    render json: {ok:true}
  end
end
