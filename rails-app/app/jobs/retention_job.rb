# TM-12 (T9): presenças, cobranças pagas, mensagens enviadas e eventos de produto (analytics_events) guardam por
# 12 meses (decisões do humano, 2026-10-31). Cobrança em aberto não é apagada, de qualquer idade.
class RetentionJob
  include Sidekiq::Job

  KEEP = 12.months

  def perform
    cutoff = KEEP.ago
    old_logs = MessageLog.where(created_at: ...cutoff)
    Attendance::Response.where(created_at: ...cutoff).delete_all
    Billing::Charge.where.not(paid_at: nil).where(created_at: ...cutoff).delete_all
    # round_id não tem cascade: mensagem nova ligada a uma rodada que vai sumir perde só o vínculo.
    MessageLog.where(round_id: old_logs.select(:id)).update_all(round_id: nil)
    AnalyticsEvent.where(occurred_at: ...cutoff).delete_all
    old_logs.delete_all # attendances da rodada vão junto (FK cascade); assistant_actions ficam com message_log_id nulo
  end
end
