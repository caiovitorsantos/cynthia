# Dispara as rotinas (fluxos de horário) vencidas e já calcula a próxima execução.
class RunDueFlowsJob
  include Sidekiq::Job

  def perform
    Flow.active.where(trigger: "schedule").where("next_run_at <= ?", Time.current).find_each do |flow|
      flow.update_columns(last_run_at: Time.current)
      next_run_at = ScheduleCalculator.next_run(flow)
      flow.update_columns(next_run_at: next_run_at)
      flow.update_columns(active: false) if flow.cron_expression.present? && next_run_at.nil?
      RunFlowJob.perform_async(flow.id)
    end
  end
end
