class CreateWhatsappGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :whatsapp_groups do |t|
      t.string   :jid, null: false
      t.string   :name
      t.integer  :participants_count
      t.datetime :synced_at

      t.timestamps
    end

    add_index :whatsapp_groups, :jid, unique: true
  end
end
