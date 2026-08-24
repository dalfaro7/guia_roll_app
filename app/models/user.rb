class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  validates :name, presence: true
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable
  
  enum :role, { operador: 0, admin: 1 }  
  
  has_many :roll_notes,
         foreign_key: :created_by_id,
         dependent: :restrict_with_error
end
