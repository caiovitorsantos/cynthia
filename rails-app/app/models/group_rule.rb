# Regra opcional ligada a um grupo, configurada em settings. Cada kind é implementado por um
# módulo que responde a:
#   provides_variable?(rule, key)          se a variável de template é desta regra
#   render_variable(rule, key, mentions)   valor da variável (nil se não for dela)
#   settings_from(params)                  settings a partir do formulário da regra
#   after_send(rule, message_log)          chamado após cada envio com sucesso ao grupo
#   handle_event(rule, event)              reação/resposta recebida no grupo
class GroupRule < ApplicationRecord
  HANDLERS = { "attendance" => "Attendance" }.freeze
  NAMES = { "attendance" => "Lista de presença" }.freeze

  belongs_to :whatsapp_group

  store_accessor :settings, :template_id

  validates :kind, inclusion: { in: HANDLERS.keys }, uniqueness: { scope: :whatsapp_group_id }

  def handler
    HANDLERS.fetch(kind).constantize
  end

  def name
    NAMES.fetch(kind)
  end
end
