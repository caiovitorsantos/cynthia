require "rails_helper"

RSpec.describe DispatchDueSchedulesJob do
  let(:template) { Template.create!(name: "T1", body: "Olá {{nome}}") }
  let(:group) { WhatsappGroup.create!(jid: "grupo@g.us", name: "Grupo") }

  it "enfileira SendScheduledMessageJob só para schedules vencidos e zera next_run_at" do
    due = Schedule.create!(
      template: template, whatsapp_group: group,
      run_at: 1.hour.ago, next_run_at: 1.minute.ago, variables: { "nome" => "Caio" }
    )
    not_due = Schedule.create!(
      template: template, whatsapp_group: group,
      run_at: 1.hour.from_now, next_run_at: 1.hour.from_now, variables: { "nome" => "Caio" }
    )

    expect(SendScheduledMessageJob).to receive(:perform_async).with(due.id)
    expect(SendScheduledMessageJob).not_to receive(:perform_async).with(not_due.id)

    described_class.new.perform

    expect(due.reload.next_run_at).to be_nil
    expect(not_due.reload.next_run_at).to be_present
  end
end
