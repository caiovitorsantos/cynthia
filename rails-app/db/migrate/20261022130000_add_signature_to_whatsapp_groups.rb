class AddSignatureToWhatsappGroups < ActiveRecord::Migration[8.1]
  def change
    add_column :whatsapp_groups, :signature, :string, default: "_🤖 Cindy_", null: false
  end
end
