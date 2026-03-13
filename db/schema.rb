# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_03_13_195205) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "bus_assignments", force: :cascade do |t|
    t.bigint "bus_id", null: false
    t.datetime "created_at", null: false
    t.string "location", null: false
    t.integer "seats_assigned"
    t.datetime "updated_at", null: false
    t.bigint "work_day_id", null: false
    t.index ["bus_id"], name: "index_bus_assignments_on_bus_id"
    t.index ["work_day_id"], name: "index_bus_assignments_on_work_day_id"
  end

  create_table "buses", force: :cascade do |t|
    t.string "alias"
    t.integer "capacity"
    t.string "company"
    t.datetime "created_at", null: false
    t.string "phone"
    t.string "plate"
    t.datetime "updated_at", null: false
  end

  create_table "guide_days", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "day_off_consumed", default: false, null: false
    t.bigint "guide_id", null: false
    t.string "location", default: "Balsa"
    t.boolean "manually_modified"
    t.bigint "modified_by_id"
    t.string "role_primary"
    t.string "role_secondary"
    t.integer "status"
    t.datetime "updated_at", null: false
    t.bigint "work_day_id", null: false
    t.index ["guide_id"], name: "index_guide_days_on_guide_id"
    t.index ["modified_by_id"], name: "index_guide_days_on_modified_by_id"
    t.index ["work_day_id"], name: "index_guide_days_on_work_day_id"
  end

  create_table "guide_skills", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "guide_id", null: false
    t.bigint "skill_id", null: false
    t.datetime "updated_at", null: false
    t.index ["guide_id", "skill_id"], name: "index_guide_skills_on_guide_id_and_skill_id", unique: true
    t.index ["guide_id"], name: "index_guide_skills_on_guide_id"
    t.index ["skill_id"], name: "index_guide_skills_on_skill_id"
  end

  create_table "guides", force: :cascade do |t|
    t.boolean "active"
    t.datetime "created_at", null: false
    t.integer "day_off_balance", default: 0, null: false
    t.datetime "day_off_balance_updated_at"
    t.date "last_priority_change_date"
    t.string "name"
    t.integer "priority"
    t.date "start_date"
    t.integer "total_worked_days"
    t.datetime "updated_at", null: false
  end

  create_table "location_slots", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "location"
    t.datetime "updated_at", null: false
    t.bigint "work_day_id", null: false
    t.index ["work_day_id"], name: "index_location_slots_on_work_day_id"
  end

  create_table "manual_day_offs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.bigint "guide_id", null: false
    t.datetime "updated_at", null: false
    t.index ["guide_id", "date"], name: "index_manual_day_offs_on_guide_id_and_date", unique: true
    t.index ["guide_id"], name: "index_manual_day_offs_on_guide_id"
  end

  create_table "monthly_balances", force: :cascade do |t|
    t.integer "balance"
    t.integer "bus_days"
    t.datetime "created_at", null: false
    t.bigint "guide_id", null: false
    t.date "month"
    t.datetime "updated_at", null: false
    t.integer "worked_days", default: 0, null: false
    t.index ["guide_id"], name: "index_monthly_balances_on_guide_id"
  end

  create_table "skills", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "slot_skills", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "location_slot_id", null: false
    t.bigint "skill_id", null: false
    t.datetime "updated_at", null: false
    t.index ["location_slot_id"], name: "index_slot_skills_on_location_slot_id"
    t.index ["skill_id"], name: "index_slot_skills_on_skill_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "role"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "work_day_versions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "snapshot"
    t.datetime "updated_at", null: false
    t.bigint "work_day_id", null: false
    t.index ["work_day_id"], name: "index_work_day_versions_on_work_day_id"
  end

  create_table "work_days", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date"
    t.integer "guides_requested"
    t.datetime "published_at"
    t.integer "status", default: 0
    t.datetime "updated_at", null: false
    t.index ["date"], name: "index_work_days_on_date", unique: true
  end

  add_foreign_key "bus_assignments", "buses"
  add_foreign_key "bus_assignments", "work_days"
  add_foreign_key "guide_days", "guides"
  add_foreign_key "guide_days", "users", column: "modified_by_id"
  add_foreign_key "guide_days", "work_days"
  add_foreign_key "guide_skills", "guides"
  add_foreign_key "guide_skills", "skills"
  add_foreign_key "location_slots", "work_days"
  add_foreign_key "manual_day_offs", "guides"
  add_foreign_key "monthly_balances", "guides"
  add_foreign_key "slot_skills", "location_slots"
  add_foreign_key "slot_skills", "skills"
  add_foreign_key "work_day_versions", "work_days"
end
