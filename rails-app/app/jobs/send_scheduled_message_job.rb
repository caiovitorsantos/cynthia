class SendScheduledMessageJob
  include Sidekiq::Job

  sidekiq_options retry: 3

  def perform(schedule_id)
    schedule = Schedule.find(schedule_id)
    result = TemplateRenderer.call(
      schedule.template, schedule.variables,
      whatsapp_group: schedule.whatsapp_group, now: Time.current.in_time_zone(schedule.timezone)
    )

    message_log = MessageLog.create!(
      schedule: schedule,
      group_jid: schedule.whatsapp_group.jid,
      rendered_body: result.body,
      status: "pending"
    )

    DeliverMessageJob.new.perform(message_log.id, result.mentioned_jids)

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
