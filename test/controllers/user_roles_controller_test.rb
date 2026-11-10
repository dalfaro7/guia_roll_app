require "test_helper"

class UserRolesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @superadmin = User.create!(name: "Super Admin", email: "superadmin@example.test",
      password: "password123", role: :admin, superadmin: true)
    @admin = User.create!(name: "Administrator", email: "administrator@example.test",
      password: "password123", role: :admin)
    @operator = User.create!(name: "Operator", email: "operator@example.test",
      password: "password123", role: :operador)
    sign_in @superadmin
  end

  test "only superadmin sees the role management page and navigation" do
    get user_roles_path

    assert_response :success
    assert_select "h1", "Roles y accesos"
    assert_select "nav a[href='#{user_roles_path}']", text: "Roles y accesos"
    assert_select "form[action='#{user_role_path(@operator)}']"
    assert_select "form[action='#{user_role_path(@superadmin)}']", count: 0
  end

  test "superadmin can change a role and the change is audited" do
    assert_difference "AuditLog.count", 1 do
      patch user_role_path(@operator), params: { user: { access_role: "contabilidad" } }
    end

    assert_redirected_to user_roles_path
    assert @operator.reload.contabilidad?
    log = AuditLog.order(:id).last
    assert_equal @superadmin.id, log.user_id
    assert_equal "update_user_role", log.action
    assert_equal @operator.id, log.auditable_id
    assert_equal "operador", log.metadata.fetch("before")
    assert_equal "contabilidad", log.metadata.fetch("after")
  end

  test "superadmin can assign HG Sarapiquí without administrator privileges" do
    patch user_role_path(@operator),
      params: { user: { access_role: "hg_sarapiqui" } }

    assert_redirected_to user_roles_path
    assert @operator.reload.hg_sarapiqui?
    assert_not @operator.superadmin?
    assert_equal "hg_sarapiqui",
      AuditLog.order(:id).last.metadata.fetch("after")
  end

  test "superadmin can promote another administrator" do
    patch user_role_path(@admin), params: { user: { access_role: "superadmin" } }

    assert_redirected_to user_roles_path
    assert @admin.reload.admin?
    assert @admin.superadmin?
  end

  test "superadmin can transfer privilege while retaining one superadmin" do
    @admin.update!(superadmin: true)

    patch user_role_path(@admin), params: { user: { access_role: "admin" } }

    assert_redirected_to user_roles_path
    assert_not @admin.reload.superadmin?
    assert @superadmin.reload.superadmin?
  end

  test "regular administrator cannot read or change roles" do
    sign_out @superadmin
    sign_in @admin

    get user_roles_path
    assert_redirected_to root_path
    patch user_role_path(@operator), params: { user: { access_role: "admin" } }
    assert_redirected_to root_path
    assert @operator.reload.operador?
    get root_path
    assert_select "nav a[href='#{user_roles_path}']", count: 0
  end

  test "operator cannot read or change roles" do
    sign_out @superadmin
    sign_in @operator

    get user_roles_path
    assert_redirected_to root_path
    patch user_role_path(@admin), params: { user: { access_role: "superadmin" } }
    assert_redirected_to root_path
    assert_not @admin.reload.superadmin?
  end

  test "superadmin cannot change their own role" do
    patch user_role_path(@superadmin), params: { user: { access_role: "operador" } }

    assert_redirected_to user_roles_path
    assert @superadmin.reload.superadmin?
    assert @superadmin.admin?
  end

  test "invalid role is rejected" do
    patch user_role_path(@operator), params: { user: { access_role: "owner" } }

    assert_redirected_to user_roles_path
    assert @operator.reload.operador?
  end

  test "superadmin privilege requires administrator role" do
    @operator.superadmin = true

    assert_not @operator.valid?
    assert @operator.errors[:superadmin].any?
  end

  test "public registration cannot request administrator or superadmin access" do
    sign_out @superadmin

    post user_registration_path, params: { user: {
      name: "New Person", email: "new-person@example.test",
      password: "password123", password_confirmation: "password123",
      role: "admin", superadmin: true
    } }

    created = User.find_by!(email: "new-person@example.test")
    assert_not created.admin?
    assert_not created.superadmin?
  end
end
