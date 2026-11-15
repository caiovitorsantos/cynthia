# Lista de membros do grupo (ex.: mensal, espera, pagou). Uma pessoa pode estar em várias.
# Vira variável de template: {{lista:chave}} (nomes) e {{mencoes:chave}} (marca as pessoas).
class MemberList < ApplicationRecord
  belongs_to :whatsapp_group
  has_and_belongs_to_many :group_participants

  validates :name, presence: true
  validates :key, presence: true, uniqueness: { scope: :whatsapp_group_id }

  before_validation { self.key ||= Template.key_for(name).presence }
end
