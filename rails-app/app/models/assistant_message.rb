# Um turno da conversa com a Cynth.ia, guardado como os blocos da API (inclusive os de
# pensamento, que precisam voltar intactos). "Nova conversa" apaga tudo; AssistantRetentionJob apaga após 30 dias.
class AssistantMessage < ApplicationRecord
  ROLES = %w[user assistant].freeze

  validates :role, inclusion: { in: ROLES }

  scope :ordered, -> { order(:id) }

  # T8/TM-11: cada chamada leva só os últimos turnos, começando num turno do usuário com texto (nunca num
  # tool_result sem o tool_use dele). Uma pergunta usa no máximo 1 + 2 × MAX_TOOL_ROUNDS turnos.
  HISTORY_LIMIT = 40

  def self.history
    recent = ordered.last(HISTORY_LIMIT)
    start = recent.index { |message| message.role == "user" && message.content.any? { |block| block["type"] == "text" } }
    recent.drop(start || recent.size).map { |message| { role: message.role, content: message.content } }
  end

  # Texto visível do turno: o que a pessoa escreveu ou a resposta dela (sem pensamento,
  # ferramentas e notas internas do painel).
  def visible_text
    content.select { |block| block["type"] == "text" && !block["text"].start_with?(AssistantAction::NOTE_PREFIX) }
      .map { |block| block["text"].sub(/\A\[[^\]]*\]\n/, "") }.join("\n").presence
  end
end
