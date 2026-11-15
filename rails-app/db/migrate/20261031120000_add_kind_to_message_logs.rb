# Expansão compatível com a versão anterior: coluna nula, código antigo a ignora (rollback seguro).
# "ai_notice" marca o aviso de IA de terceiro (RF-28); nulo = mensagem comum.
class AddKindToMessageLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :message_logs, :kind, :string
    add_index :message_logs, [ :group_jid, :kind ]
  end
end
