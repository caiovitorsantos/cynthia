# Idioma das mensagens que a Cynth.ia gera no grupo (nomes de mês, assinatura padrão).
class AddLocaleToWhatsappGroups < ActiveRecord::Migration[8.1]
  def change
    add_column :whatsapp_groups, :locale, :string, default: "pt-BR", null: false
  end
end
