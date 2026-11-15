# TM-11 (T8): o chat da Cynth.ia (painel) e as propostas guardam por 30 dias (decisão do humano, 2026-10-31).
# O histórico é cortado num turno do usuário com texto, para a conversa que sobra não começar num
# tool_result órfão (a API recusaria).
class AssistantRetentionJob
  include Sidekiq::Job

  KEEP = 30.days

  def perform
    cutoff = KEEP.ago
    first_kept = AssistantMessage.where(created_at: cutoff..).where(role: "user")
      .where("content @> ?", [ { type: "text" } ].to_json).minimum(:id)
    (first_kept ? AssistantMessage.where(id: ...first_kept) : AssistantMessage.all).delete_all
    AssistantAction.where(created_at: ...cutoff).delete_all
  end
end
