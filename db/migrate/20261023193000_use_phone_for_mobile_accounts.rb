class UsePhoneForMobileAccounts < ActiveRecord::Migration[8.1]
  def up
    raise 'Hay cuentas móviles existentes: asigna sus teléfonos antes de migrar.' if select_value('SELECT COUNT(*) FROM mobile_accounts').to_i > 0
    add_column :mobile_accounts, :phone, :string, null: false
    add_index :mobile_accounts, :phone, unique: true
    change_column_null :mobile_accounts, :email, true
  end
  def down
    raise ActiveRecord::IrreversibleMigration, 'El acceso móvil utiliza teléfonos; no convertirlos automáticamente en correos.'
  end
end
