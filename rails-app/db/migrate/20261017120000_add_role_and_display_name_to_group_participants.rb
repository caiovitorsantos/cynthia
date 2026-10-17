class AddRoleAndDisplayNameToGroupParticipants < ActiveRecord::Migration[8.1]
  def change
    add_column :group_participants, :role, :string
    add_column :group_participants, :display_name, :string
  end
end
