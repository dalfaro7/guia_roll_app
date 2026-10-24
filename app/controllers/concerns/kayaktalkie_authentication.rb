module KayaktalkieAuthentication
  private
  def authenticate_kayaktalkie!
    bearer=request.authorization.to_s.delete_prefix('Bearer ')
    @kayaktalkie_session=KayaktalkieSession.authenticate(bearer.presence || session[:kayaktalkie_token])
    @account=@kayaktalkie_session&.kayaktalkie_account
    @browser=bearer.blank?
    return if @account
    if request.path.start_with?('/api/')
      render json: {error: 'Inicia sesión en KayakTalkie.'}, status: :unauthorized
    else
      redirect_to kayaktalkie_login_path
    end
  end
  def require_kayaktalkie_admin!
    head :forbidden unless @account.admin?
  end
  def require_kayaktalkie_map!
    head :forbidden unless @account.map_access?
  end
end
