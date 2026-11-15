# S-01 (WHA-16): turnos do chat do painel gravados antes da redação do RF-29 têm telefone e valor de variável,
# e AssistantMessage.history os reenviava a cada turno. Apaga o histórico (equivale a "nova conversa").
# Só dados; o código anterior funciona com a tabela vazia (rollback seguro).
class ResetAssistantHistoryForRf29 < ActiveRecord::Migration[8.1]
  def up = execute("DELETE FROM assistant_messages")
  def down = nil
end
