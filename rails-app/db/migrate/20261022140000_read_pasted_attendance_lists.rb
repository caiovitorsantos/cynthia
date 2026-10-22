# Listas de presença coladas no grupo: convidados sem cadastro (só o nome) e nomes da lista que
# não batem com nenhum membro, para o admin associar.
class ReadPastedAttendanceLists < ActiveRecord::Migration[8.1]
  def change
    change_column_null :attendances, :group_participant_id, true
    add_column :attendances, :guest_name, :string
    add_index :attendances, [ :message_log_id, :guest_name ], unique: true, where: "guest_name IS NOT NULL"
    add_column :message_logs, :unmatched_names, :jsonb, default: [], null: false
  end
end
