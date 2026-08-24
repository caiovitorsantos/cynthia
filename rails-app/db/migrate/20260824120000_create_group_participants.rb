class CreateGroupParticipants < ActiveRecord::Migration[8.1]
  def change
    create_table :group_participants do |t|
      t.references :whatsapp_group, null: false, foreign_key: true
      t.string   :jid, null: false
      t.string   :phone_number
      t.string   :name
      t.datetime :synced_at

      t.timestamps
    end

    add_index :group_participants, [ :whatsapp_group_id, :jid ], unique: true
  end
end
