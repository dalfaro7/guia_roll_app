# ==============================
# GUIDES SEED DATA
# ==============================

guides_data = [
  ["Alcides Enríquez Paniagua", 3],
  ["Allan Alvarez Solano", 2],
  ["Anthony Brayan González Marín", 3],
  ["Axel Andrés Fonseca Díaz", 3],
  ["Axel Gonzalez Lopez", 3],
  ["Braulio Duran Enriquez", 1],
  ["Carlos Gonzalez Alfaro", 1],
  ["Carlos Rosales Rivas", 2],
  ["Carlos Vasquez Cisneros", 1],
  ["Darwin Guerrero Fonseca", 2],
  ["Didier Alfaro Rivera", 1],
  ["Edwin Treviño Lopez", 2],
  ["Elvis Gabriel Cruz Ponce", 2],
  ["Erick Quesada Duarte", 2],
  ["Fabricio Marin Carrillo", 3],
  ["Fernando Cascante", 3],
  ["Imanol Campos Duran", 2],
  ["Jilbin Martínez Laguna", 3],
  ["Jose Victor Alvarez", 1],
  ["Joseph Madrigal Berrocal", 3],
  ["Juan Inocente Rosales Rivas", 0],
  ["Junior Duarte Badilla", 2],
  ["Mariam Victoria Araya Rojas", 3],
  ["Matías Ignacio Vasquez Poblete", 3],
  ["Moisés Hernández Jarquin", 3],
  ["Roberto Alfaro Sibaja", 2],
  ["Tom Leon Oviedo", 2],
  ["Victor Fonseca Campos", 0],
  ["William Molina Vásquez", 2],
  ["Yader Romero Astorga", 2]
]

guides_data.each do |name, priority|
  guide = Guide.find_or_initialize_by(name: name)

  guide.priority = priority
  guide.active = true
  guide.total_worked_days ||= 0
  guide.start_date ||= Date.today

  guide.save!
end

puts "Guides seeded successfully."


skills = [
  "Elite",
  "Kayaker",
  "ClassIV",
  "Photographer",
  "Busguide",
  "HG",
  "ClassIII",
  "B1",
  "Computer",
  "Certified"
]

skills.each do |skill_name|
  Skill.find_or_create_by!(name: skill_name)
end