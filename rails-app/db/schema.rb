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

ActiveRecord::Schema[8.1].define(version: 2026_10_22_130000) do
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

  create_table "flows", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "command"
    t.datetime "created_at", null: false
    t.string "cron_expression"
    t.datetime "last_run_at"
    t.string "name", null: false
    t.datetime "next_run_at"
    t.datetime "run_at"
    t.jsonb "steps", default: [], null: false
    t.string "timezone", default: "America/Sao_Paulo", null: false
    t.string "trigger", null: false
    t.datetime "updated_at", null: false
    t.bigint "whatsapp_group_id", null: false
    t.index ["active", "next_run_at"], name: "index_flows_on_active_and_next_run_at"
    t.index ["whatsapp_group_id"], name: "index_flows_on_whatsapp_group_id"
  end

  create_table "group_participants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "display_name"
    t.string "jid", null: false
    t.string "name"
    t.string "phone_number"
    t.datetime "synced_at"
    t.datetime "updated_at", null: false
    t.bigint "whatsapp_group_id", null: false
    t.index ["whatsapp_group_id", "jid"], name: "index_group_participants_on_whatsapp_group_id_and_jid", unique: true
    t.index ["whatsapp_group_id"], name: "index_group_participants_on_whatsapp_group_id"
  end

  create_table "group_participants_member_lists", id: false, force: :cascade do |t|
    t.bigint "group_participant_id", null: false
    t.bigint "member_list_id", null: false
    t.index ["group_participant_id"], name: "index_group_participants_member_lists_on_group_participant_id"
    t.index ["member_list_id", "group_participant_id"], name: "index_list_members_unique", unique: true
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

  create_table "member_lists", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.bigint "whatsapp_group_id", null: false
    t.index ["whatsapp_group_id", "key"], name: "index_member_lists_on_whatsapp_group_id_and_key", unique: true
    t.index ["whatsapp_group_id"], name: "index_member_lists_on_whatsapp_group_id"
  end

  create_table "message_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.bigint "flow_id"
    t.string "group_jid"
    t.boolean "opens_round", default: false, null: false
    t.text "rendered_body"
    t.bigint "round_id"
    t.datetime "sent_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.string "wa_message_id"
    t.index ["flow_id"], name: "index_message_logs_on_flow_id"
    t.index ["round_id"], name: "index_message_logs_on_round_id"
    t.index ["wa_message_id"], name: "index_message_logs_on_wa_message_id"
  end

  create_table "templates", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.jsonb "default_variables", default: {}, null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.bigint "whatsapp_group_id"
    t.index ["whatsapp_group_id", "name"], name: "index_templates_on_whatsapp_group_id_and_name", unique: true
    t.index ["whatsapp_group_id"], name: "index_templates_on_whatsapp_group_id"
  end

  create_table "whatsapp_groups", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "jid", null: false
    t.string "list_empty_text", default: "", null: false
    t.string "list_style", default: "numbered", null: false
    t.string "name"
    t.integer "participants_count"
    t.string "signature", default: "_🤖 Cindy_", null: false
    t.datetime "synced_at"
    t.datetime "updated_at", null: false
    t.jsonb "variables", default: {}, null: false
    t.index ["jid"], name: "index_whatsapp_groups_on_jid", unique: true
  end

  add_foreign_key "attendances", "group_participants", on_delete: :cascade
  add_foreign_key "attendances", "message_logs", on_delete: :cascade
  add_foreign_key "flows", "whatsapp_groups", on_delete: :cascade
  add_foreign_key "group_participants", "whatsapp_groups"
  add_foreign_key "group_participants_member_lists", "group_participants", on_delete: :cascade
  add_foreign_key "group_participants_member_lists", "member_lists", on_delete: :cascade
  add_foreign_key "group_rules", "whatsapp_groups"
  add_foreign_key "member_lists", "whatsapp_groups", on_delete: :cascade
  add_foreign_key "message_logs", "flows", on_delete: :nullify
  add_foreign_key "message_logs", "message_logs", column: "round_id"
  add_foreign_key "templates", "whatsapp_groups", on_delete: :cascade
end
