require "rails_helper"

RSpec.describe Schedule do
  let(:template) { Template.create!(name: "Presença", body: "PRESENÇA {{data}}\n{{mencoes:mensal}}") }
  let(:group) { WhatsappGroup.create!(jid: "g1@g.us", name: "Grupo 1") }

  it "não exige valor para variáveis automáticas nem para as das regras do grupo" do
    group.group_rules.create!(kind: "attendance")

    expect(Schedule.new(template: template, whatsapp_group: group, cron_expression: "0 14 * * 2")).to be_valid
  end

  it "exige valor para variável de regra que o grupo não tem" do
    schedule = Schedule.new(template: template, whatsapp_group: group, cron_expression: "0 14 * * 2")

    expect(schedule).not_to be_valid
    expect(schedule.errors[:variables].first).to include("mencoes:mensal")
  end

  it "aceita variáveis definidas no grupo" do
    template = Template.create!(name: "Cobrança", body: "PIX: {{pix}}")
    group.update!(variables: { "pix" => "pix@exemplo.com" })

    expect(Schedule.new(template: template, whatsapp_group: group, cron_expression: "0 9 1 * *")).to be_valid
  end
end
