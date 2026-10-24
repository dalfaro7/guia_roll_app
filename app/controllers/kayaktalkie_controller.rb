class KayaktalkieController < ActionController::Base
  protect_from_forgery with: :exception
  layout 'kayaktalkie'
  include KayaktalkieAuthentication
  before_action :authenticate_kayaktalkie!, only: :show
  rate_limit to: 15, within: 15.minutes, only: :create,
    with: -> { render plain: 'Demasiados intentos. Espera 15 minutos.', status: :too_many_requests }
  def new
  end
  def create
    account = KayaktalkieAccount.find_by(phone: KayaktalkieAccount.normalize_phone(params[:phone]))
    if account&.available? && account.valid_password?(params[:password])
      reset_session
      session[:kayaktalkie_token] = KayaktalkieSession.issue!(account)
      redirect_to account.map_access? ? tracking_path : kayaktalkie_path
    else
      @error = 'Teléfono o contraseña incorrectos.'
      render :new, status: :unprocessable_entity
    end
  end
  def show
  end
  def destroy
    KayaktalkieSession.authenticate(session[:kayaktalkie_token])&.destroy!
    reset_session
    redirect_to kayaktalkie_login_path
  end
end
