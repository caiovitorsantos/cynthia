class SendScheduledMessageJob
  include Sidekiq::Job

  sidekiq_options retry: 3

  def perform(schedule_id)
    schedule = Schedule.find(schedule_id)
    variables = schedule.template.default_variables.merge(schedule.variables)
    result = TemplateRenderer.call(schedule.template, variables, whatsapp_group: schedule.whatsapp_group)

    message_log = MessageLog.create!(
      schedule: schedule,
      group_jid: schedule.whatsapp_group.jid,
      rendered_body: result.body,
      status: "pending"
    )

    begin
      SendGuard.check!(group_jid: schedule.whatsapp_group.jid, message: result.body)
      WaClient.send_message(group_jid: schedule.whatsapp_group.jid, message: result.body, mentions: result.mentioned_jids)
      message_log.update!(status: "sent", sent_at: Time.current)
    rescue WaClient::NotConnected => e
      # Problema de sessão, não transiente: não deixa o Sidekiq re-tentar.
      message_log.update!(status: "failed", error_message: e.message)
    rescue SendGuard::DailyCapReachedError, SendGuard::DuplicateMessageError => e
      # Bloqueio deliberado de política: não adianta re-tentar em segundos.
      message_log.update!(status: "failed", error_message: e.message)
    rescue SendGuard::ThrottledError, WaClient::Error => e
      # Transiente: deixa o retry padrão do Sidekiq tentar de novo em breve.
      message_log.update!(status: "failed", error_message: e.message)
      raise
    end

    reschedule(schedule)
  end

  private

  def reschedule(schedule)
    schedule.update!(last_run_at: Time.current)

    next_run_at = ScheduleCalculator.next_run(schedule)
    schedule.update!(next_run_at: next_run_at)
    schedule.update!(active: false) if schedule.cron_expression.present? && next_run_at.nil?
  end
end
