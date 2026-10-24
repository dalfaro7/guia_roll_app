class KayaktalkiePasswordsController < ActionController::Base
  protect_from_forgery with: :exception
  layout 'kayaktalkie'
  rate_limit to: 5, within: 15.minutes, only: :create, with: -> { render plain: 'Espera unos minutos antes de intentarlo de nuevo.', status: :too_many_requests }
  rate_limit to: 20, within: 15.minutes, only: :update, with: -> { head :too_many_requests }
  def new; end
  def create
    unless KayaktalkieMailer.configured?
      @error='La recuperación por correo está en configuración. Inténtalo más tarde.'
      return render :new, status: :service_unavailable
    end
    KayaktalkiePasswordReset.request(params[:email])
    @notice='Si el correo corresponde a una cuenta activa, recibirás un enlace para restablecer tu contraseña.'
    render :new
  end
  def edit
    response.headers['Referrer-Policy']='no-referrer'
    response.headers['Cache-Control']='no-store'
    @token=params[:token]
  end
  def update
    response.headers['Referrer-Policy']='no-referrer'
    response.headers['Cache-Control']='no-store'
    KayaktalkiePasswordReset.consume!(params[:token],params[:password],params[:password_confirmation])
    session.delete(:kayaktalkie_token)
    redirect_to kayaktalkie_login_path, notice: 'Contraseña actualizada. Inicia sesión de nuevo.'
  rescue KayaktalkiePasswordReset::InvalidToken
    @error='El enlace no es válido o ya venció. Solicita uno nuevo.'
    render :new, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    @token=params[:token]; @error=e.record.errors.full_messages.join(', ')
    render :edit, status: :unprocessable_entity
  end
end
