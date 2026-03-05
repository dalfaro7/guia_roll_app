class Skill < ApplicationRecord
  has_many :guide_skills, dependent: :destroy
  has_many :guides, through: :guide_skills

  validates :name, presence: true, uniqueness: true
end
