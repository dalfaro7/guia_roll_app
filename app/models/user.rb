class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  validates :name, presence: true
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  enum :role, { operador: 0, admin: 1, recursos_humanos: 2, contabilidad: 3, hg_sarapiqui: 4 }

  ACCESS_ROLE_LABELS = {
    "operador" => "Operador",
    "admin" => "Administrador",
    "recursos_humanos" => "Recursos Humanos",
    "contabilidad" => "Contabilidad",
    "superadmin" => "Super Admin",
    "hg_sarapiqui" => "HG Sarapiquí"
  }.freeze

  validate :superadmin_requires_admin

  def access_role
    superadmin? ? "superadmin" : role
  end

  has_many :roll_notes,
         foreign_key: :created_by_id,
         dependent: :restrict_with_error

  private

  def superadmin_requires_admin
    errors.add(:superadmin, "requiere el rol Administrador") if superadmin? && !admin?
  end
end
