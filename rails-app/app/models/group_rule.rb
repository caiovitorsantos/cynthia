# Regra opcional ligada a um grupo, configurado em settings. Cada kind é implementado por um
# módulo que responde a:
#   provides_variable?(rule, key)                 se a variável de template é desta regra
#   render_variable(rule, key, mentions)          valor da variável (nil se não for dela)
#   settings_from(params)                         settings a partir do formulário da regra
#   before_message(rule, step, now)               antes de renderizar um passo "Enviar template"
#   prepare_message(rule, message_log, template)  antes de salvar cada mensagem enviada ao grupo
#   handle_event(rule, event)                     reação, resposta ou lista colada no grupo
class GroupRule < ApplicationRecord
  HANDLERS = { "attendance" => "Attendance", "billing" => "Billing" }.freeze
  NAMES = { "attendance" => "Lista de presença", "billing" => "Cobrança mensal" }.freeze

  belongs_to :whatsapp_group

  validates :kind, inclusion: { in: HANDLERS.keys }, uniqueness: { scope: :whatsapp_group_id }

  def handler
    HANDLERS.fetch(kind).constantize
  end

  def name
    NAMES.fetch(kind)
  end
end
