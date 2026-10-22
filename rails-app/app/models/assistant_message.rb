# Um turno da conversa com a Cynth.ia, guardado como os blocos da API (inclusive os de
# pensamento, que precisam voltar intactos). A conversa só cresce; "nova conversa" apaga tudo.
class AssistantMessage < ApplicationRecord
  ROLES = %w[user assistant].freeze

  validates :role, inclusion: { in: ROLES }

  scope :ordered, -> { order(:id) }

  def self.history
    ordered.map { |message| { role: message.role, content: message.content } }
  end

  # Texto visível do turno: o que a pessoa escreveu ou a resposta dela (sem pensamento,
  # ferramentas e notas internas do painel).
  def visible_text
    content.select { |block| block["type"] == "text" && !block["text"].start_with?(AssistantAction::NOTE_PREFIX) }
      .map { |block| block["text"].sub(/\A\[[^\]]*\]\n/, "") }.join("\n").presence
  end
end
