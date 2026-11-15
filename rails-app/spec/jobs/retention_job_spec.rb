require "rails_helper"

RSpec.describe RetentionJob do
  it "TM-12: apaga presenças, cobranças pagas e mensagens com mais de 12 meses; cobrança em aberto fica" do
    group = WhatsappGroup.create!(jid: "g1@g.us", name: "Vôlei")
    ana = GroupParticipant.create!(whatsapp_group: group, jid: "1@lid", name: "e2e-Ana")
    old = 13.months.ago
    old_round = MessageLog.create!(group_jid: group.jid, rendered_body: "r", status: "sent", opens_round: true, created_at: old)
    new_round = MessageLog.create!(group_jid: group.jid, rendered_body: "r2", status: "sent", opens_round: true)
    linked = MessageLog.create!(group_jid: group.jid, rendered_body: "lembrete", status: "sent", round_id: old_round.id)
    old_answer = Attendance::Response.create!(message_log: old_round, group_participant: ana, status: "confirmed", created_at: old)
    new_answer = Attendance::Response.create!(message_log: new_round, group_participant: ana, status: "confirmed")
    paid_old = Billing::Charge.create!(whatsapp_group: group, group_participant: ana, kind: "mensal", period: "2025-08", paid_at: old, created_at: old)
    open_old = Billing::Charge.create!(whatsapp_group: group, group_participant: ana, kind: "mensal", period: "2025-09", created_at: old)
    paid_new = Billing::Charge.create!(whatsapp_group: group, group_participant: ana, kind: "mensal", period: "2026-09", paid_at: 1.day.ago)
    old_event = AnalyticsEvent.create!(name: "admin_logado", occurred_at: old)
    new_event = AnalyticsEvent.create!(name: "admin_logado", occurred_at: 1.day.ago)

    described_class.new.perform

    expect(MessageLog.where(id: old_round.id)).to be_empty
    expect(Attendance::Response.where(id: old_answer.id)).to be_empty
    expect(Billing::Charge.where(id: paid_old.id)).to be_empty
    expect(Billing::Charge.where(id: [ open_old.id, paid_new.id ]).count).to eq(2)
    expect(new_answer.reload).to be_present
    expect(linked.reload.round_id).to be_nil
    expect(AnalyticsEvent.ids).to eq([ new_event.id ])
    expect(AnalyticsEvent.exists?(old_event.id)).to be(false)
  end

  it "roda todo dia pelo sidekiq-cron, junto com a retenção do assistente" do
    schedule = YAML.load_file(Rails.root.join("config/schedule.yml"))
    expect(schedule.values.map { |job| job["class"] }).to include("RetentionJob", "AssistantRetentionJob")
    expect(schedule.values.map { |job| Fugit.parse_cron(job["cron"]) }).to all(be_present)
  end
end
