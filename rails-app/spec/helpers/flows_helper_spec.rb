require "rails_helper"

RSpec.describe FlowsHelper, type: :helper do
  it "pluraliza em português" do
    expect(helper.rough_frequency_in_words(7 * 86_400)).to eq("a cada 7 dias")
    expect(helper.rough_frequency_in_words(86_400)).to eq("a cada 1 dia")
    expect(helper.rough_frequency_in_words(2 * 3_600)).to eq("a cada 2 horas")
    expect(helper.rough_frequency_in_words(300)).to eq("a cada 5 minutos")
  end

  it "descreve os horários que o seletor gera e cai na frequência para o resto" do
    expect(helper.cron_in_words("0 14 * * 2")).to eq("toda terça às 14:00")
    expect(helper.cron_in_words("30 9 * * 0")).to eq("todo domingo às 09:30")
    expect(helper.cron_in_words("0 9 * * 1-5")).to eq("de segunda a sexta às 09:00")
    expect(helper.cron_in_words("0 20 * * 2,4")).to eq("ter e qui às 20:00")
    expect(helper.cron_in_words("0 9 * * *")).to eq("todo dia às 09:00")
    expect(helper.cron_in_words("0 9 1 * *")).to eq("todo dia 1 do mês às 09:00")
    expect(helper.cron_in_words("*/15 * * * *")).to eq("a cada 15 minutos")
  end

  it "lê o cron de volta para o seletor" do
    expect(helper.simple_cron("5 8 * * 1,3,5")).to eq(mode: "weekly", time: "08:05", weekdays: [ 1, 3, 5 ])
    expect(helper.simple_cron("0 9 15 * *")).to eq(mode: "monthly", time: "09:00", monthday: 15)
    expect(helper.simple_cron("0 9 1 1 *")).to be_nil
  end
end
