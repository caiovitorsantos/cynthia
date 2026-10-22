# A Cynth.ia ganhou voz própria (seca, entediada): várias assinaturas, sorteadas por mensagem.
# Grupos com a assinatura padrão anterior passam para as novas; personalizadas ficam como estão.
class DeadpanSignatures < ActiveRecord::Migration[8.1]
  SIGNATURES = "_😒 Cynth.ia_ | _— Cynth.ia, contra a vontade_ | _Cynth.ia. De nada, eu acho._ | _ugh. — Cynth.ia_".freeze

  def up
    change_column_default :whatsapp_groups, :signature, SIGNATURES
    execute "UPDATE whatsapp_groups SET signature = #{connection.quote(SIGNATURES)} WHERE signature = '_🤖 Cynth.ia_'"
  end

  def down
    change_column_default :whatsapp_groups, :signature, "_🤖 Cynth.ia_"
  end
end
