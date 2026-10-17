class CreateAttendances < ActiveRecord::Migration[8.1]
  def change
    add_column :templates, :attendance, :boolean, default: false, null: false

    add_column :message_logs, :wa_message_id, :string
    add_index :message_logs, :wa_message_id
    # Mensagens de acompanhamento (lista atualizada, lembrete) apontam para a rodada que acompanham.
    add_reference :message_logs, :round, foreign_key: { to_table: :message_logs }

    create_table :attendances do |t|
      t.references :message_log, null: false, foreign_key: true
      t.references :group_participant, null: false, foreign_key: true
      t.string :status, null: false
      t.timestamps
    end
    add_index :attendances, [ :message_log_id, :group_participant_id ], unique: true
  end
end
