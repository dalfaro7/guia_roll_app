class KayaktalkieFieldReportsController < ActionController::API
  include ActionController::Cookies
  include ActionController::RequestForgeryProtection
  include KayaktalkieAuthentication
  before_action :authenticate_kayaktalkie!
  before_action :check_csrf, only: [:create, :resolve]
  before_action :require_kayaktalkie_map!, only: :resolve
  rate_limit to: 30, within: 1.minute, only: :create, with: -> { render json: {error: 'Espera un minuto antes de enviar más reportes.'}, status: :too_many_requests }
  def index
    scope = KayaktalkieFieldReport.visible_to(@account).unexpired.where(resolved_at: nil).includes(:kayaktalkie_account, :kayaktalkie_team)
    cursor = params[:before].to_i
    scope = scope.where('id < ?', cursor) if cursor.positive?
    rows = scope.order(id: :desc).limit(101).to_a
    response.headers['Cache-Control'] = 'no-store'
    render json: {items: rows.first(100).map(&:client_profile), next_before: rows.size > 100 ? rows[99].id : nil}
  end
  def show
    report=KayaktalkieFieldReport.visible_to(@account).find_by(id:params[:id])
    return render json: {error:'Este reporte venció o ya no está disponible.'}, status: :not_found unless report && report.expires_at>Time.current && !report.resolved_at
    response.headers['Cache-Control']='no-store'
    render json: report.client_profile
  end
  def create
    return render json: {error: "La carga de fotos no está habilitada."}, status: :unprocessable_entity if params[:photo].present?
    team = @account.kayaktalkie_teams.find_by(id: params[:team_id])
    team = KayaktalkieTeam.find_by(id: params[:team_id]) if @account.admin?
    return render json: {error: 'Equipo no autorizado.'}, status: :forbidden unless team
    existing = KayaktalkieFieldReport.visible_to(@account).find_by(kayaktalkie_account: @account, client_id: params[:client_id])
    return render json: {error: "Este reporte ya venció."}, status: :gone if existing && existing.expires_at <= Time.current
    return render json: existing.client_profile if existing
    report = KayaktalkieFieldReport.new(params.permit(:client_id, :kind, :animal, :description, :latitude, :longitude, :accuracy, :observed_at))
    report.kayaktalkie_account = @account; report.kayaktalkie_team = team
    report.save!
    render json: report.client_profile, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: {error: e.record.errors.full_messages.join(', ')}, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    render json: KayaktalkieFieldReport.visible_to(@account).find_by!(kayaktalkie_account: @account, client_id: params[:client_id]).client_profile
  end
  def resolve
    report = KayaktalkieFieldReport.visible_to(@account).unexpired.find(params[:id])
    report.with_lock { report.update!(resolved_at: Time.current, resolved_by: @account) unless report.resolved_at }
    render json: {ok: true}
  end
  private
  def check_csrf
    head :forbidden if @browser && !valid_authenticity_token?(session, request.headers['X-CSRF-Token'])
  end
end
