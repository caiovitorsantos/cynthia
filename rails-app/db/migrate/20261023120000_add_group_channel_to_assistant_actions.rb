# Propostas feitas pela Cynth.ia dentro de um grupo (marcada numa mensagem): ficam ligadas à
# mensagem dela no grupo e são confirmadas por um admin respondendo "sim" a essa mensagem.
class AddGroupChannelToAssistantActions < ActiveRecord::Migration[8.1]
  def change
    add_column :assistant_actions, :channel, :string, default: "panel", null: false
    add_reference :assistant_actions, :message_log, foreign_key: { on_delete: :nullify }
  end
end
