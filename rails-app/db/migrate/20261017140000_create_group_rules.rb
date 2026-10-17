class CreateGroupRules < ActiveRecord::Migration[8.1]
  def up
    create_table :group_rules do |t|
      t.references :whatsapp_group, null: false, foreign_key: true
      t.string :kind, null: false
      t.jsonb :settings, default: {}, null: false
      t.timestamps
    end
    add_index :group_rules, [ :whatsapp_group_id, :kind ], unique: true

    # Templates marcados como lista de presença viram a regra dos grupos que os agendam.
    execute <<~SQL
      INSERT INTO group_rules (whatsapp_group_id, kind, settings, created_at, updated_at)
      SELECT DISTINCT ON (schedules.whatsapp_group_id) schedules.whatsapp_group_id, 'attendance',
             jsonb_build_object('template_id', templates.id::text), NOW(), NOW()
      FROM schedules JOIN templates ON templates.id = schedules.template_id
      WHERE templates.attendance
    SQL
    remove_column :templates, :attendance

    # A sincronização apaga participantes com delete_all (sem callbacks): as respostas vão junto.
    remove_foreign_key :attendances, :group_participants
    add_foreign_key :attendances, :group_participants, on_delete: :cascade
    remove_foreign_key :attendances, :message_logs
    add_foreign_key :attendances, :message_logs, on_delete: :cascade
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
