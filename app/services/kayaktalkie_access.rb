class KayaktalkieAccess
  def self.assign!(account, attributes:, team_ids:, channel_ids:)
    teams=Array(team_ids).reject(&:blank?).map(&:to_s).uniq
    ids=Array(channel_ids).reject(&:blank?).map(&:to_s).uniq
    selected=VoiceChannel.enabled.where(id: ids)
    raise ArgumentError, 'Equipo o canal inválido.' unless KayaktalkieTeam.where(id: teams).count==teams.size && selected.count==ids.size
    raise ArgumentError, 'Cada canal debe pertenecer a un equipo asignado.' unless (selected.pluck(:kayaktalkie_team_id).map(&:to_s)-teams).empty?
    KayaktalkieAccount.transaction do
      account.lock! if account.persisted?
      old=account.persisted? ? account.allowed_channels.to_a : []
      account.assign_attributes(attributes)
      account.save!
      account.kayaktalkie_teams=KayaktalkieTeam.where(id: teams)
      account.voice_channels=selected
      current=account.available? ? account.allowed_channels.pluck(:id) : []
      (old.map(&:id)-current).each { |id| VoiceRevokeAccessJob.perform_later(account.id,id) }
    end
  end
end
