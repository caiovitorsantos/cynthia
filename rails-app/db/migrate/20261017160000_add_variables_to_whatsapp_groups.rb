class AddVariablesToWhatsappGroups < ActiveRecord::Migration[8.1]
  def change
    add_column :whatsapp_groups, :variables, :jsonb, default: {}, null: false
  end
end
