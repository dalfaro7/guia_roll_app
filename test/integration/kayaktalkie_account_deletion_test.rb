require 'test_helper'
class KayaktalkieAccountDeletionTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  setup do
    @admin = KayaktalkieAccount.create!(name: 'Delete admin', phone: '89994001', password: 'Deletion-test-123456', role: 'admin', active: true)
    @channel = VoiceChannel.find_by!(room_key: VoiceFloor::ROOM)
    @target = KayaktalkieAccount.new
    KayaktalkieAccess.assign!(@target, attributes: {name: 'Delete staff', phone: '89994002', password: 'Deletion-test-123456', role: 'staff', active: true}, team_ids: [@channel.kayaktalkie_team_id], channel_ids: [@channel.id])
  end
  def login(account)
    post '/kayaktalkie/login', params: {phone: account.phone, password: 'Deletion-test-123456'}
  end
  test 'admin confirms removal and sessions are revoked without deleting historical identity or channels' do
    token = KayaktalkieSession.issue!(@target)
    login(@admin)
    get tracking_accounts_path
    assert_select '.account-channel-badge', text: /Arenal Rafting Team/
    get confirm_delete_tracking_account_path(@target)
    assert_response :success
    assert_select 'strong', text: @target.name
    delete tracking_account_path(@target)
    assert_nil @target.reload.deleted_at
    assert_enqueued_with(job: VoiceRevokeAccessJob) do
      delete tracking_account_path(@target), params: {confirm_delete: '1'}
    end
    assert_redirected_to tracking_accounts_path
    assert @target.reload.deleted_at
    assert_not @target.active?
    assert_nil KayaktalkieSession.authenticate(token)
    assert_empty @target.voice_channels
    assert_empty @target.kayaktalkie_teams
    assert VoiceChannel.exists?(@channel.id)
    assert KayaktalkieAccount.exists?(@target.id)
    get tracking_accounts_path
    assert_select '.existing-account', text: /Delete staff/, count: 0
    post '/api/login', params: {phone: @target.phone, password: 'Deletion-test-123456'}
    assert_response :unauthorized
    assert_not @target.update(active: true)
  end
  test 'staff cannot delete and admin cannot delete themselves' do
    login(@target)
    delete tracking_account_path(@admin), params: {confirm_delete: '1'}
    assert_response :forbidden
    login(@admin)
    delete tracking_account_path(@admin), params: {confirm_delete: '1'}
    assert_redirected_to tracking_accounts_path
    assert_nil @admin.reload.deleted_at
  end
end
