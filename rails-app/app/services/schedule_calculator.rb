class ScheduleCalculator
  class << self
    def next_run(schedule, from: Time.current)
      if schedule.cron_expression.present?
        recurring_next_run(schedule, from)
      else
        one_off_next_run(schedule)
      end
    end

    private

    def one_off_next_run(schedule)
      return nil if schedule.last_run_at.present?

      schedule.run_at
    end

    def recurring_next_run(schedule, from)
      cron = Fugit.parse_cron("#{schedule.cron_expression} #{schedule.timezone}")
      return nil unless cron

      cron.next_time(from).to_t
    end
  end
end
