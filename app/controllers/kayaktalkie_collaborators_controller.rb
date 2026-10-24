class KayaktalkieCollaboratorsController < ActionController::Base
  include KayaktalkieAuthentication
  protect_from_forgery with: :exception
  layout 'kayaktalkie'
  before_action :authenticate_kayaktalkie!
  before_action :require_kayaktalkie_map!
  def index
    load_data
  end
  def create
    save(KayaktalkieAccount.new(created_by: @account), true)
  end
  def update
    account=manageable.find_by(id:params[:id])
    return head :not_found unless account
    save(account, false)
  end
  private
  def manageable
    scope=KayaktalkieAccount.where(role:'staff',created_by_id:@account.id)
    # Reassignment by an admin removes the former operator's management access.
    scope.where.not(id: KayaktalkieTeamMembership.where.not(kayaktalkie_team_id:@account.kayaktalkie_team_ids).select(:kayaktalkie_account_id))
  end
  def load_data
    @accounts=manageable.includes(:kayaktalkie_teams,:voice_channels).order(:name)
    @teams=@account.kayaktalkie_teams.order(:name)
    @channels=@account.allowed_channels.where(kayaktalkie_team_id:@teams.select(:id))
  end
  def save(account, creating)
    load_data
    teams=Array(params[:team_ids]).reject(&:blank?).map(&:to_s).uniq
    channels=Array(params[:voice_channel_ids]).reject(&:blank?).map(&:to_s).uniq
    unless teams.any? && (teams-@teams.ids.map(&:to_s)).empty? && (channels-@channels.ids.map(&:to_s)).empty?
      return head :forbidden
    end
    attrs=params.require(:kayaktalkie_account).permit(:name,:phone,:email,:password,:active,:location_enabled).to_h
    attrs.delete('password') if !creating && attrs['password'].blank?
    attrs['role']='staff'
    KayaktalkieAccess.assign!(account,attributes:attrs,team_ids:teams,channel_ids:channels)
    redirect_to kayaktalkie_collaborators_path,notice:'Colaborador guardado.'
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    @error=e.message;load_data;render :index,status: :unprocessable_entity
  end
end
