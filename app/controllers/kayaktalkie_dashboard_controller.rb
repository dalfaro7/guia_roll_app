# URL compatibility for existing bookmarks; authorization belongs only to KayakTalkie.
class KayaktalkieDashboardController < ActionController::Base
  include KayaktalkieAuthentication
  protect_from_forgery with: :exception
  layout 'kayaktalkie'
  before_action :authenticate_kayaktalkie!
  before_action :require_kayaktalkie_map!, only: [:index, :voice]
  before_action :require_kayaktalkie_admin!, except: [:index, :voice]
  def index
    render layout: false
  end
  def voice
    redirect_to tracking_path(anchor: 'voicePanel')
  end
  def accounts
    load_accounts
  end
  def create_team
    @team=KayaktalkieTeam.new(params.require(:kayaktalkie_team).permit(:name))
    if @team.save
      redirect_to tracking_accounts_path, notice: 'Equipo creado.'
    else
      invalid(@team.errors.full_messages.join(', '))
    end
  end
  def create_channel
    channel=VoiceChannel.new(params.require(:voice_channel).permit(:name,:kayaktalkie_team_id))
    channel.room_key="team-#{SecureRandom.hex(12)}"
    channel.save ? redirect_to(tracking_accounts_path, notice: 'Canal creado.') : invalid(channel.errors.full_messages.join(', '))
  end
  def create_account
    account=KayaktalkieAccount.new
    save_account(account, creating: true)
  end
  def update_channels
    save_account(KayaktalkieAccount.find(params[:id]), creating: false)
  end
  private
  def save_account(account, creating:)
    attrs=params.require(:kayaktalkie_account).permit(:name,:phone,:email,:password,:role,:active,:location_enabled)
    attrs.delete(:password) if !creating && attrs[:password].blank?
    # Do not let the currently signed-in admin lock themselves out.
    if account.id == @account.id && ((attrs[:role].present? && attrs[:role]!='admin') || attrs[:active]=='0')
      return invalid('Otro administrador debe cambiar tu propio acceso.')
    end
    KayaktalkieAccess.assign!(account, attributes: attrs, team_ids: params[:team_ids], channel_ids: params[:voice_channel_ids])
    redirect_to tracking_accounts_path, notice: 'Cuenta y permisos guardados.'
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    invalid(e.message)
  end
  def load_accounts
    @channels=VoiceChannel.includes(:kayaktalkie_team).enabled
    @accounts=KayaktalkieAccount.includes(:kayaktalkie_teams,:voice_channels).order(:name)
    @teams=KayaktalkieTeam.order(:name)
  end
  def invalid(message)
    @error=message; load_accounts; render :accounts, status: :unprocessable_entity
  end
end
