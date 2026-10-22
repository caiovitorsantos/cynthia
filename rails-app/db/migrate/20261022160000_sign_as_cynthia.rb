# A persona passou a se chamar Cynth.ia: novo padrão da assinatura, e grupos que ainda usam o
# padrão antigo passam para o novo (assinaturas personalizadas ficam como estão).
class SignAsCynthia < ActiveRecord::Migration[8.1]
  def up
    change_column_default :whatsapp_groups, :signature, "_🤖 Cynth.ia_"
    execute "UPDATE whatsapp_groups SET signature = '_🤖 Cynth.ia_' WHERE signature = '_🤖 Cindy_'"
  end

  def down
    change_column_default :whatsapp_groups, :signature, "_🤖 Cindy_"
  end
end
