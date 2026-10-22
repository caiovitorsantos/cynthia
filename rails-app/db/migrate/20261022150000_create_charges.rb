# Recurso "Cobrança mensal": uma cobrança por mensalidade (membro × mês) e por diária de avulso
# (pessoa × dia jogado), marcada como paga com 💰 numa lista colada ou pelo painel.
class CreateCharges < ActiveRecord::Migration[8.1]
  def change
    create_table :charges do |t|
      t.references :whatsapp_group, null: false, foreign_key: { on_delete: :cascade }
      t.references :group_participant, foreign_key: { on_delete: :cascade }
      t.string :guest_name
      t.string :period, null: false # "2026-09"
      t.string :kind, null: false # mensal / avulso
      t.date :date # dia jogado (avulso)
      t.datetime :paid_at
      t.timestamps
      t.index [ :whatsapp_group_id, :period, :kind, :date, :group_participant_id, :guest_name ], unique: true, nulls_not_distinct: true, name: "index_charges_unique"
    end

    add_column :message_logs, :opens_billing, :boolean, default: false, null: false
  end
end
