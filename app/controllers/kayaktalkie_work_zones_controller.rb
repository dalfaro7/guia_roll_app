class KayaktalkieWorkZonesController < ActionController::API
  include ActionController::Cookies
  include ActionController::RequestForgeryProtection
  include KayaktalkieAuthentication
  before_action :authenticate_kayaktalkie!
  before_action :require_kayaktalkie_map!
  before_action :check_csrf, except: :index
  def index
    response.headers['Cache-Control']='no-store'
    render json: {admin: @account.admin?, teams: teams.order(:name).select(:id,:name), operators: operators.map { |a| {id:a.id,name:a.name,team_ids:a.kayaktalkie_team_ids} }, zones: scope.order(:name)}
  end
  def create
    team=teams.find(params[:team_id])
    owner=operators.find(params[:operator_id].presence || @account.id)
    zone=team.kayaktalkie_work_zones.create!(fields.merge(operator:owner))
    render json: zone, status: :created
  end
  def update
    zone=scope.find(params[:id]);zone.update!(fields);render json: zone
  end
  def destroy
    scope.find(params[:id]).destroy!;head :no_content
  end
  rescue_from ActiveRecord::RecordNotFound do
    render json: {error:'Zona o equipo no autorizado.'}, status: :not_found
  end
  rescue_from ActiveRecord::RecordInvalid do |e|
    render json: {error:e.record.errors.full_messages.join(', ')}, status: :unprocessable_entity
  end
  private
  def teams = @account.admin? ? KayaktalkieTeam.all : @account.kayaktalkie_teams
  def operators
    @account.admin? ? KayaktalkieAccount.where(role:'operator',active:true) : KayaktalkieAccount.where(id:@account.id,role:'operator',active:true)
  end
  def scope
    zones=KayaktalkieWorkZone.where(kayaktalkie_team_id:teams.select(:id))
    @account.admin? ? zones : zones.where(operator_id:@account.id)
  end
  def fields = params.permit(:name,:latitude,:longitude,:radius_m)
  def check_csrf
    head :forbidden if @browser && !valid_authenticity_token?(session,request.headers['X-CSRF-Token'])
  end
end
