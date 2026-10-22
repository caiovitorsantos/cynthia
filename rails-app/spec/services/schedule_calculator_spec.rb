require "rails_helper"

RSpec.describe ScheduleCalculator do
  describe ".next_run" do
    context "quando one-off" do
      it "retorna run_at se ainda não foi executado" do
        schedule = Flow.new(run_at: Time.zone.parse("2026-09-01 10:00"), last_run_at: nil)

        expect(described_class.next_run(schedule)).to eq(schedule.run_at)
      end

      it "retorna nil se já foi executado (não reagenda)" do
        schedule = Flow.new(run_at: Time.zone.parse("2026-09-01 10:00"), last_run_at: Time.current)

        expect(described_class.next_run(schedule)).to be_nil
      end
    end

    context "quando recorrente" do
      it "calcula a próxima execução respeitando America/Sao_Paulo" do
        schedule = Flow.new(cron_expression: "0 9 * * 1-5", timezone: "America/Sao_Paulo")
        from = Time.utc(2026, 8, 20, 21, 0, 0) # quinta, 18h em SP

        next_run = described_class.next_run(schedule, from: from)

        expect(next_run.in_time_zone("America/Sao_Paulo").strftime("%H:%M")).to eq("09:00")
        # SP é UTC-3 o ano todo (sem horário de verão desde 2019)
        expect(next_run.utc.hour).to eq(12)
      end

      it "atravessa a troca de horário de verão (America/New_York)" do
        schedule = Flow.new(cron_expression: "0 9 * * *", timezone: "America/New_York")

        # sábado 7/mar/2026, 15h em NY (ainda EST, UTC-5), após o 9h de sábado
        from = Time.utc(2026, 3, 7, 20, 0, 0)

        next_run = described_class.next_run(schedule, from: from)

        # domingo 8/mar é o "spring forward": 9h de domingo já é EDT (UTC-4)
        expect(next_run.in_time_zone("America/New_York").strftime("%H:%M")).to eq("09:00")
        expect(next_run.utc.hour).to eq(13)
      end
    end

    it "retorna nil se a expressão cron for inválida" do
      schedule = Flow.new(cron_expression: "not a cron", timezone: "America/Sao_Paulo")

      expect(described_class.next_run(schedule)).to be_nil
    end
  end
end
