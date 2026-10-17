require "rails_helper"

RSpec.describe Schedule do
  it "não exige valor para variáveis automáticas" do
    template = Template.create!(name: "Presença", body: "PRESENÇA {{data}}\n{{mencoes_mensais}}")
    group = WhatsappGroup.create!(jid: "g1@g.us", name: "Grupo 1")

    schedule = Schedule.new(template: template, whatsapp_group: group, cron_expression: "0 14 * * 2")

    expect(schedule).to be_valid
  end
end
