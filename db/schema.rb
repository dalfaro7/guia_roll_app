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

ActiveRecord::Schema[8.1].define(version: 2026_10_25_030000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "audit_logs", force: :cascade do |t|
    t.string "action"
    t.bigint "auditable_id"
    t.string "auditable_type"
    t.datetime "created_at", null: false
    t.jsonb "metadata"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "work_day_id"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
    t.index ["work_day_id"], name: "index_audit_logs_on_work_day_id"
  end

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
    t.text "status_note"
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
    t.integer "fairness_entry_roll_days", default: 0, null: false
    t.date "fairness_started_on"
    t.date "last_priority_change_date"
    t.string "name"
    t.integer "priority"
    t.date "start_date"
    t.integer "total_worked_days"
    t.datetime "updated_at", null: false
  end

  create_table "kayaktalkie_accounts", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.string "email"
    t.string "encrypted_password", null: false
    t.boolean "location_enabled", default: true, null: false
    t.string "name", null: false
    t.string "phone", null: false
    t.string "reset_password_digest"
    t.datetime "reset_password_sent_at"
    t.string "role", default: "staff", null: false
    t.datetime "updated_at", null: false
    t.index "lower((email)::text)", name: "unique_kayak_email", unique: true, where: "(email IS NOT NULL)"
    t.index ["created_by_id"], name: "index_kayaktalkie_accounts_on_created_by_id"
    t.index ["phone"], name: "index_kayaktalkie_accounts_on_phone", unique: true
    t.index ["reset_password_digest"], name: "index_kayaktalkie_accounts_on_reset_password_digest", unique: true
    t.check_constraint "length(TRIM(BOTH FROM name)) > 0", name: "kayaktalkie_name"
    t.check_constraint "role::text = ANY (ARRAY['admin'::character varying, 'operator'::character varying, 'staff'::character varying]::text[])", name: "kayaktalkie_role"
  end

  create_table "kayaktalkie_positions", force: :cascade do |t|
    t.float "accuracy", null: false
    t.datetime "captured_at", null: false
    t.datetime "created_at", null: false
    t.bigint "kayaktalkie_account_id", null: false
    t.float "latitude", null: false
    t.float "longitude", null: false
    t.datetime "received_at", null: false
    t.jsonb "speed_estimate", default: {}, null: false
    t.float "speed_kmh"
    t.jsonb "speed_samples", default: [], null: false
    t.bigint "team_ids_at_capture", default: [], null: false, array: true
    t.datetime "updated_at", null: false
    t.index ["kayaktalkie_account_id"], name: "index_kayaktalkie_positions_on_kayaktalkie_account_id"
    t.index ["kayaktalkie_account_id"], name: "one_kayaktalkie_position", unique: true
  end

  create_table "kayaktalkie_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "kayaktalkie_account_id", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["kayaktalkie_account_id"], name: "index_kayaktalkie_sessions_on_kayaktalkie_account_id"
    t.index ["token_digest"], name: "index_kayaktalkie_sessions_on_token_digest", unique: true
  end

  create_table "kayaktalkie_speed_alerts", force: :cascade do |t|
    t.string "account_name", null: false
    t.datetime "acknowledged_at"
    t.datetime "created_at", null: false
    t.date "day", null: false
    t.datetime "ended_at"
    t.datetime "first_at", null: false
    t.bigint "kayaktalkie_account_id", null: false
    t.datetime "last_at", null: false
    t.float "peak_kmh", null: false
    t.string "source", default: "gps", null: false
    t.bigint "team_ids_at_capture", default: [], null: false, array: true
    t.datetime "updated_at", null: false
    t.index ["day", "first_at"], name: "index_kayaktalkie_speed_alerts_on_day_and_first_at"
    t.index ["kayaktalkie_account_id", "source"], name: "one_open_kayaktalkie_speed_alert_per_source", unique: true, where: "(ended_at IS NULL)"
    t.index ["kayaktalkie_account_id"], name: "index_kayaktalkie_speed_alerts_on_kayaktalkie_account_id"
    t.check_constraint "source::text = ANY (ARRAY['gps'::character varying, 'estimated'::character varying]::text[])", name: "kayaktalkie_speed_alert_source"
  end

  create_table "kayaktalkie_team_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "kayaktalkie_account_id", null: false
    t.bigint "kayaktalkie_team_id", null: false
    t.datetime "updated_at", null: false
    t.index ["kayaktalkie_account_id", "kayaktalkie_team_id"], name: "unique_kayaktalkie_team_member", unique: true
    t.index ["kayaktalkie_account_id"], name: "index_kayaktalkie_team_memberships_on_kayaktalkie_account_id"
    t.index ["kayaktalkie_team_id"], name: "index_kayaktalkie_team_memberships_on_kayaktalkie_team_id"
  end

  create_table "kayaktalkie_teams", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "location_slots", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "location"
    t.integer "passengers", default: 0
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

  create_table "office_day_credits", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date"
    t.text "notes"
    t.bigint "office_employee_id", null: false
    t.string "source"
    t.datetime "updated_at", null: false
    t.boolean "used", default: false, null: false
    t.date "used_on"
    t.index ["office_employee_id"], name: "index_office_day_credits_on_office_employee_id"
  end

  create_table "office_employee_days", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date"
    t.string "day_off_source"
    t.boolean "holiday_paid", default: false, null: false
    t.text "notes"
    t.bigint "office_day_credit_id", null: false
    t.bigint "office_employee_id", null: false
    t.bigint "office_vacation_credit_id", null: false
    t.integer "status"
    t.datetime "updated_at", null: false
    t.index ["office_day_credit_id"], name: "index_office_employee_days_on_office_day_credit_id"
    t.index ["office_employee_id"], name: "index_office_employee_days_on_office_employee_id"
    t.index ["office_vacation_credit_id"], name: "index_office_employee_days_on_office_vacation_credit_id"
  end

  create_table "office_employees", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "department"
    t.string "name"
    t.integer "restricted_day_off_weekday"
    t.datetime "updated_at", null: false
  end

  create_table "office_holidays", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date"
    t.boolean "double_pay", default: true, null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "office_overtimes", force: :cascade do |t|
    t.boolean "approved", default: true, null: false
    t.datetime "created_at", null: false
    t.date "date"
    t.integer "minutes", default: 0, null: false
    t.bigint "office_employee_id", null: false
    t.string "reason"
    t.datetime "updated_at", null: false
    t.index ["office_employee_id"], name: "index_office_overtimes_on_office_employee_id"
  end

  create_table "office_vacation_credits", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.text "notes"
    t.bigint "office_employee_id", null: false
    t.string "source", default: "legacy", null: false
    t.datetime "updated_at", null: false
    t.boolean "used", default: false, null: false
    t.date "used_on"
    t.index ["office_employee_id", "date", "source"], name: "idx_office_vacation_credits_unique", unique: true
    t.index ["office_employee_id", "used"], name: "index_office_vacation_credits_on_office_employee_id_and_used"
    t.index ["office_employee_id"], name: "index_office_vacation_credits_on_office_employee_id"
  end

  create_table "roll_note_guide_days", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "guide_day_id", null: false
    t.bigint "roll_note_id", null: false
    t.datetime "updated_at", null: false
    t.index ["guide_day_id"], name: "index_roll_note_guide_days_on_guide_day_id"
    t.index ["roll_note_id", "guide_day_id"], name: "index_roll_note_guide_days_unique", unique: true
    t.index ["roll_note_id"], name: "index_roll_note_guide_days_on_roll_note_id"
  end

  create_table "roll_notes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_id", null: false
    t.text "note", null: false
    t.integer "note_type", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "work_day_id", null: false
    t.index ["created_by_id"], name: "index_roll_notes_on_created_by_id"
    t.index ["work_day_id"], name: "index_roll_notes_on_work_day_id"
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

  create_table "solid_cable_messages", force: :cascade do |t|
    t.binary "channel", null: false
    t.bigint "channel_hash", null: false
    t.datetime "created_at", null: false
    t.binary "payload", null: false
    t.index ["channel"], name: "index_solid_cable_messages_on_channel"
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.integer "byte_size", null: false
    t.datetime "created_at", null: false
    t.binary "key", null: false
    t.bigint "key_hash", null: false
    t.binary "value", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "name"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "role"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "voice_channels", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.bigint "kayaktalkie_team_id", null: false
    t.string "name", null: false
    t.string "room_key", null: false
    t.datetime "updated_at", null: false
    t.index ["kayaktalkie_team_id"], name: "index_voice_channels_on_kayaktalkie_team_id"
    t.index ["room_key"], name: "index_voice_channels_on_room_key", unique: true
  end

  create_table "voice_floors", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.string "holder_identity"
    t.string "holder_name"
    t.string "lease_id"
    t.string "room_key", null: false
    t.datetime "updated_at", null: false
    t.index ["room_key"], name: "index_voice_floors_on_room_key", unique: true
  end

  create_table "voice_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "kayaktalkie_account_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "voice_channel_id", null: false
    t.index ["kayaktalkie_account_id", "voice_channel_id"], name: "unique_voice_membership", unique: true
    t.index ["kayaktalkie_account_id"], name: "index_voice_memberships_on_kayaktalkie_account_id"
    t.index ["voice_channel_id"], name: "index_voice_memberships_on_voice_channel_id"
  end

  create_table "weather_reports", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "reported_at", null: false
    t.string "source_name", default: "ChatGPT", null: false
    t.string "source_uid", null: false
    t.string "source_url", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["reported_at"], name: "index_weather_reports_on_reported_at"
    t.index ["source_uid"], name: "index_weather_reports_on_source_uid", unique: true
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

  add_foreign_key "audit_logs", "users"
  add_foreign_key "audit_logs", "work_days"
  add_foreign_key "bus_assignments", "buses"
  add_foreign_key "bus_assignments", "work_days"
  add_foreign_key "guide_days", "guides"
  add_foreign_key "guide_days", "users", column: "modified_by_id"
  add_foreign_key "guide_days", "work_days"
  add_foreign_key "guide_skills", "guides"
  add_foreign_key "guide_skills", "skills"
  add_foreign_key "kayaktalkie_accounts", "kayaktalkie_accounts", column: "created_by_id"
  add_foreign_key "kayaktalkie_positions", "kayaktalkie_accounts"
  add_foreign_key "kayaktalkie_sessions", "kayaktalkie_accounts"
  add_foreign_key "kayaktalkie_speed_alerts", "kayaktalkie_accounts"
  add_foreign_key "kayaktalkie_team_memberships", "kayaktalkie_accounts"
  add_foreign_key "kayaktalkie_team_memberships", "kayaktalkie_teams"
  add_foreign_key "location_slots", "work_days"
  add_foreign_key "manual_day_offs", "guides"
  add_foreign_key "monthly_balances", "guides"
  add_foreign_key "office_day_credits", "office_employees"
  add_foreign_key "office_employee_days", "office_day_credits"
  add_foreign_key "office_employee_days", "office_employees"
  add_foreign_key "office_employee_days", "office_vacation_credits"
  add_foreign_key "office_overtimes", "office_employees"
  add_foreign_key "office_vacation_credits", "office_employees"
  add_foreign_key "roll_note_guide_days", "guide_days"
  add_foreign_key "roll_note_guide_days", "roll_notes"
  add_foreign_key "roll_notes", "users", column: "created_by_id"
  add_foreign_key "roll_notes", "work_days"
  add_foreign_key "slot_skills", "location_slots"
  add_foreign_key "slot_skills", "skills"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "voice_channels", "kayaktalkie_teams"
  add_foreign_key "voice_memberships", "kayaktalkie_accounts"
  add_foreign_key "voice_memberships", "voice_channels"
  add_foreign_key "work_day_versions", "work_days"
end
