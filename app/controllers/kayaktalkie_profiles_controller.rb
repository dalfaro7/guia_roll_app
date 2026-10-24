class KayaktalkieProfilesController < ActionController::Base
  include KayaktalkieAuthentication
  protect_from_forgery with: :exception
  layout 'kayaktalkie'
  before_action :authenticate_kayaktalkie!
  def edit; end
  def update
    unless @account.valid_password?(params[:current_password])
      @error='La contraseña actual no es correcta.'
      return render :edit, status: :unprocessable_entity
    end
    attrs={email: params[:email]}
    attrs.merge!(password: params[:password],password_confirmation:params[:password_confirmation].to_s) if params[:password].present?
    @account.update!(attrs)
    if params[:password].present?
      session.delete(:kayaktalkie_token)
      redirect_to kayaktalkie_login_path, notice: 'Contraseña actualizada. Inicia sesión de nuevo.'
    else
      redirect_to kayaktalkie_profile_path, notice: 'Correo guardado.'
    end
  rescue ActiveRecord::RecordInvalid => e
    @error=e.record.errors.full_messages.join(', ');render :edit,status: :unprocessable_entity
  end
end
