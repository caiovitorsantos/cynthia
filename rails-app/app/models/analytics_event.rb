# Evento de produto do tracking-plan.md (ADR-011). Só IDs internos, códigos, datas e contagens: nunca nome,
# telefone, JID, group_jid ou texto de mensagem (TT-13). Gravar é melhor esforço: falha vira log e nunca
# interrompe o envio nem o webhook (savepoint, para não abortar a transação de quem chamou).
class AnalyticsEvent < ApplicationRecord
  NAMES = %w[admin_logado fluxo_executado mensagem_enviada mensagem_falhou rodada_aberta presenca_registrada
             presenca_desfeita cobranca_aberta cobranca_paga cobranca_desmarcada sessao_conectada sessao_caiu].freeze

  validates :name, inclusion: { in: NAMES }
  validate :scalar_properties

  def self.track(name, **properties)
    transaction(requires_new: true) { create!(name: name.to_s, occurred_at: Time.current, properties: properties) }
  rescue StandardError => e
    Rails.logger.warn("AnalyticsEvent #{name} não gravado: #{e.class}")
    nil
  end

  private

  # Trava contra PII por engano: só inteiro, booleano, nulo ou texto curto sem "@" nem 8+ dígitos seguidos
  # (código, período, data ISO). Não pega nome; o que entra é decidido nos pontos de emissão.
  def scalar_properties
    ok = properties.values.all? { |value| value.nil? || value == true || value == false || value.is_a?(Integer) || (value.is_a?(String) && value.size <= 32 && !value.match?(/@|\d{8}/)) }
    errors.add(:properties, "só aceita inteiro, booleano, nulo ou código curto") unless ok
  end
end
