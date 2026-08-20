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

ActiveRecord::Schema[8.1].define(version: 2026_08_20_120004) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "message_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "group_jid"
    t.text "rendered_body"
    t.bigint "schedule_id"
    t.datetime "sent_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["schedule_id"], name: "index_message_logs_on_schedule_id"
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

  add_foreign_key "message_logs", "schedules"
  add_foreign_key "schedules", "templates"
  add_foreign_key "schedules", "whatsapp_groups"
end
