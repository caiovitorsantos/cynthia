# Quem é admin do grupo no WhatsApp (vem da sincronização).
class AddAdminToGroupParticipants < ActiveRecord::Migration[8.1]
  def change
    add_column :group_participants, :admin, :boolean, default: false, null: false
  end
end
