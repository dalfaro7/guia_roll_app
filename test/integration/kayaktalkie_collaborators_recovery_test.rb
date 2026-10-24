require 'test_helper'
class KayaktalkieCollaboratorsRecoveryTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  setup do
    @a=VoiceChannel.find_by!(room_key:VoiceFloor::ROOM)
    @b=VoiceChannel.find_by!(room_key:'abccanyoning-team')
    @operator=KayaktalkieAccount.new
    KayaktalkieAccess.assign!(@operator,attributes:{name:'Operator',phone:'89993001',password:'Account-test-123456',role:'operator',email:'operator@example.test'},team_ids:[@a.kayaktalkie_team_id],channel_ids:[@a.id])
  end
  def login
    post '/kayaktalkie/login',params:{phone:@operator.phone,password:'Account-test-123456'}
  end
  def payload
    {kayaktalkie_account:{name:'New staff',phone:'89993002',password:'Staff-test-123456',role:'admin',email:'staff@example.test'},team_ids:[@a.kayaktalkie_team_id],voice_channel_ids:[@a.id]}
  end
  test 'operator creates staff only and cannot assign channels outside own grants' do
    login
    post '/kayaktalkie/collaborators',params:payload
    assert_response :redirect
    staff=KayaktalkieAccount.find_by!(phone:'+50689993002')
    assert_equal 'staff',staff.role
    assert_equal @operator.id,staff.created_by_id
    assert_equal [@a.id],staff.allowed_channels.ids
    bad=payload;bad[:kayaktalkie_account][:phone]='89993003';bad[:voice_channel_ids]=[@b.id]
    assert_no_difference('KayaktalkieAccount.count'){post '/kayaktalkie/collaborators',params:bad}
    assert_response :forbidden
    patch "/kayaktalkie/collaborators/#{@operator.id}",params:payload
    assert_response :not_found
    staff.kayaktalkie_teams << @b.kayaktalkie_team
    patch "/kayaktalkie/collaborators/#{staff.id}",params:payload
    assert_response :not_found
  end
  test 'staff cannot manage and map renders escaped operator identity' do
    login;get '/tracking';assert_select '.kayak-account-corner strong',text:'Operator'
    @operator.update!(role:'staff')
    get '/kayaktalkie/collaborators';assert_response :forbidden
  end
  test 'profile requires current password and cannot change role' do
    login
    patch '/kayaktalkie/profile',params:{email:'new@example.test',current_password:'wrong',role:'admin'}
    assert_response :unprocessable_entity;assert_equal 'operator@example.test',@operator.reload.email
    patch '/kayaktalkie/profile',params:{email:'NEW@example.test',current_password:'Account-test-123456',role:'admin'}
    assert_response :redirect;assert_equal 'new@example.test',@operator.reload.email;assert_equal 'operator',@operator.role
  end
  test 'reset is generic and token is one-use expires and revokes sessions' do
    post '/kayaktalkie/password',params:{email:'missing@example.test'};missing=response.body
    assert_enqueued_with(job:KayaktalkieMailDeliveryJob){post '/kayaktalkie/password',params:{email:' OPERATOR@example.test '}}
    assert_equal missing,response.body
    job=enqueued_jobs.reverse.find{|j|j[:job]==KayaktalkieMailDeliveryJob}
    token=job[:args][3]['args'][1]
    assert_not_equal token,@operator.reload.reset_password_digest
    bearer=KayaktalkieSession.issue!(@operator)
    patch '/kayaktalkie/password',params:{token:token,password:'Changed-test-123456',password_confirmation:'different'}
    assert_response :unprocessable_entity
    patch '/kayaktalkie/password',params:{token:token,password:'Changed-test-123456',password_confirmation:'Changed-test-123456'}
    assert_response :redirect;assert_nil KayaktalkieSession.authenticate(bearer)
    assert @operator.reload.valid_password?('Changed-test-123456')
    assert_raises(KayaktalkiePasswordReset::InvalidToken){KayaktalkiePasswordReset.consume!(token,'Another-test-123456','Another-test-123456')}
    KayaktalkiePasswordReset.request(@operator.email)
    token=enqueued_jobs.reverse.find{|j|j[:job]==KayaktalkieMailDeliveryJob}[:args][3]['args'][1]
    travel 61.minutes do
      assert_raises(KayaktalkiePasswordReset::InvalidToken){KayaktalkiePasswordReset.consume!(token,'Another-test-123456','Another-test-123456')}
    end
  end
  test 'mailer uses fixed sender and public URL not request host' do
    KayaktalkiePasswordReset.request(@operator.email)
    token=enqueued_jobs.reverse.find{|j|j[:job]==KayaktalkieMailDeliveryJob}[:args][3]['args'][1]
    mail=KayaktalkieMailer.password_reset(@operator.id,token).message
    assert_equal ['webmaster@arenalrafting.com'],mail.from
    assert_includes mail.body.to_s,'https://guia-roll-app.onrender.com/kayaktalkie/password/edit'
    assert_includes mail.body.to_s,token
    @operator.update!(email:'other@example.test')
    assert_nil @operator.reload.reset_password_digest
  end
end
