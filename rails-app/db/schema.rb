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

ActiveRecord::Schema[8.1].define(version: 2026_10_17_150000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "attendances", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "group_participant_id", null: false
    t.bigint "message_log_id", null: false
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["group_participant_id"], name: "index_attendances_on_group_participant_id"
    t.index ["message_log_id", "group_participant_id"], name: "index_attendances_on_message_log_id_and_group_participant_id", unique: true
    t.index ["message_log_id"], name: "index_attendances_on_message_log_id"
  end

  create_table "group_participants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "display_name"
    t.string "jid", null: false
    t.string "name"
    t.string "phone_number"
    t.string "role"
    t.datetime "synced_at"
    t.datetime "updated_at", null: false
    t.bigint "whatsapp_group_id", null: false
    t.index ["whatsapp_group_id", "jid"], name: "index_group_participants_on_whatsapp_group_id_and_jid", unique: true
    t.index ["whatsapp_group_id"], name: "index_group_participants_on_whatsapp_group_id"
  end

  create_table "group_rules", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "updated_at", null: false
    t.bigint "whatsapp_group_id", null: false
    t.index ["whatsapp_group_id", "kind"], name: "index_group_rules_on_whatsapp_group_id_and_kind", unique: true
    t.index ["whatsapp_group_id"], name: "index_group_rules_on_whatsapp_group_id"
  end

  create_table "message_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "group_jid"
    t.text "rendered_body"
    t.bigint "round_id"
    t.bigint "schedule_id"
    t.datetime "sent_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.string "wa_message_id"
    t.index ["round_id"], name: "index_message_logs_on_round_id"
    t.index ["schedule_id"], name: "index_message_logs_on_schedule_id"
    t.index ["wa_message_id"], name: "index_message_logs_on_wa_message_id"
  end

  create_table "schedules", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "cron_expression"
    t.datetime "last_run_at"
    t.datetime "next_run_at"
    t.datetime "run_at"
    t.bigint "template_id", null: false
    t.string "timezone", default: "America/Sao_Paulo", null: false
    t.datetime "updated_at", null: false
    t.jsonb "variables", default: {}, null: false
    t.bigint "whatsapp_group_id", null: false
    t.index ["active", "next_run_at"], name: "index_schedules_on_active_and_next_run_at"
    t.index ["template_id"], name: "index_schedules_on_template_id"
    t.index ["whatsapp_group_id"], name: "index_schedules_on_whatsapp_group_id"
  end

  create_table "templates", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.jsonb "default_variables", default: {}, null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_templates_on_name", unique: true
  end

  create_table "whatsapp_groups", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "jid", null: false
    t.string "name"
    t.integer "participants_count"
    t.datetime "synced_at"
    t.datetime "updated_at", null: false
    t.index ["jid"], name: "index_whatsapp_groups_on_jid", unique: true
  end

  add_foreign_key "attendances", "group_participants", on_delete: :cascade
  add_foreign_key "attendances", "message_logs", on_delete: :cascade
  add_foreign_key "group_participants", "whatsapp_groups"
  add_foreign_key "group_rules", "whatsapp_groups"
  add_foreign_key "message_logs", "message_logs", column: "round_id"
  add_foreign_key "message_logs", "schedules"
  add_foreign_key "schedules", "templates"
  add_foreign_key "schedules", "whatsapp_groups"
end
