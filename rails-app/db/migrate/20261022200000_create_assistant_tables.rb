# Assistente da Cynth.ia no painel: a conversa (blocos crus da API, só acrescentados) e as ações
# que ela propõe e só são executadas quando o usuário confirma.
class CreateAssistantTables < ActiveRecord::Migration[8.1]
  def change
    create_table :assistant_messages do |t|
      t.string :role, null: false # user / assistant
      t.jsonb :content, null: false, default: []
      t.timestamps
    end

    create_table :assistant_actions do |t|
      t.string :kind, null: false
      t.jsonb :payload, null: false, default: {}
      t.string :status, null: false, default: "pending" # pending / done / failed / cancelled
      t.text :result
      t.boolean :reported, null: false, default: false # já contado à Cynth.ia no turno seguinte
      t.timestamps
    end
  end
end
