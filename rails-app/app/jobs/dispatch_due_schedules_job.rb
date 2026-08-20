class DispatchDueSchedulesJob
  include Sidekiq::Job

  def perform
    Schedule.where(active: true).where("next_run_at <= ?", Time.current).find_each do |schedule|
      schedule.update!(next_run_at: nil)
      SendScheduledMessageJob.perform_async(schedule.id)
    end
  end
end
