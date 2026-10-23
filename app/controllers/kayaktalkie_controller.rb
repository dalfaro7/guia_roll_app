class KayaktalkieController < ActionController::Base
  protect_from_forgery with: :exception
  layout 'kayaktalkie'
  before_action :require_office!, only: :show
  rate_limit to: 15, within: 15.minutes, only: :create,
    with: -> { render plain: 'Demasiados intentos. Espera 15 minutos.', status: :too_many_requests }
  def new
  end
  def create
    account = MobileAccount.find_by(phone: MobileAccount.normalize_phone(params[:phone]))
    if account&.office_account? && account.available? && account.valid_password?(params[:password])
      reset_session
      session[:kayaktalkie_token] = MobileSession.issue!(account)
      redirect_to kayaktalkie_path
    else
      @error = 'Teléfono o contraseña incorrectos para el acceso de oficina.'
      render :new, status: :unprocessable_entity
    end
  end
  def show
  end
  def destroy
    MobileSession.authenticate(session[:kayaktalkie_token])&.destroy!
    reset_session
    redirect_to kayaktalkie_login_path
  end
  private
  def require_office!
    mobile = MobileSession.authenticate(session[:kayaktalkie_token])
    @account = mobile&.mobile_account
    redirect_to kayaktalkie_login_path unless @account&.office_account?
  end
end
