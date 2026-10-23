class GuideTrackingController < ApplicationController
  before_action :require_admin!
  def index
    render layout: false
  end
  def voice
    redirect_to tracking_path(anchor: "voicePanel")
  end
  def accounts
    @channels = VoiceChannel.enabled
    @accounts = MobileAccount.includes(:guide).order(:phone)
    @guides = Guide.active.order(:name)
  end
  def create_channel
    channel = VoiceChannel.new(name: params.require(:voice_channel).permit(:name)[:name], room_key: "team-#{SecureRandom.hex(12)}")
    if channel.save
      redirect_to tracking_accounts_path, notice: 'Canal creado. Asigna los colaboradores autorizados.'
    else
      redirect_to tracking_accounts_path, alert: channel.errors.full_messages.join(', ')
    end
  end
  def update_channels
    account = MobileAccount.find(params[:id])
    requested = Array(params[:voice_channel_ids]).reject(&:blank?).map(&:to_s).uniq
    channels = VoiceChannel.enabled.where(id: requested)
    return head :unprocessable_entity unless channels.count == requested.length
    VoiceChannelAccess.assign(account, channels)
    redirect_to tracking_accounts_path, notice: 'Canales actualizados. Los permisos se comprueban en cada conexion y turno.'
  end
  def create_account
    account = MobileAccount.new(params.require(:mobile_account).permit(:guide_id, :name, :account_type, :phone, :password, :location_enabled))
    if account.office_account?
      account.guide_id = nil
      account.location_enabled = false
    end
    requested = Array(params.dig(:mobile_account, :voice_channel_ids)).reject(&:blank?).map(&:to_s).uniq
    selected_channels = VoiceChannel.enabled.where(id: requested)
    return head :unprocessable_entity unless selected_channels.count == requested.length
    account.voice_channels = selected_channels
    if account.save
      redirect_to tracking_accounts_path, notice: 'Cuenta KayakTalkie creada. Entrega el teléfono y la contraseña al colaborador.'
    else
      @accounts = MobileAccount.includes(:guide).order(:phone)
      @guides = Guide.active.order(:name)
      @channels = VoiceChannel.enabled
      @error = account.errors.full_messages.join(', ')
      render :accounts, status: :unprocessable_entity
    end
  end
end
