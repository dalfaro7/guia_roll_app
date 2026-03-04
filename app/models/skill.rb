class Skill < ApplicationRecord
  has_many :guide_skills
  has_many :guides, through: :guide_skills
end
