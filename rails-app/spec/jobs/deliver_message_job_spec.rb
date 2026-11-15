require "rails_helper"

RSpec.describe DeliverMessageJob do
  let(:group) { WhatsappGroup.create!(jid: "5511977776666-1600000000@g.us", name: "Vôlei") }
  let(:log) { MessageLog.create!(group_jid: group.jid, rendered_body: "Oi @5511988887777", status: "pending") }
  let(:wa_send) { "#{ENV.fetch('WA_SERVICE_URL')}/send" }

  def events(name) = AnalyticsEvent.where(name: name).map(&:properties)

  it "RF-18: até 3 retries, e só nos erros transientes (throttle e erro do wa-service)" do
    expect(described_class.get_sidekiq_options["retry"]).to eq(3)

    stub_request(:post, wa_send).to_return(status: 500)
    4.times do |i|
      expect { described_class.new.perform(log.id) }.to raise_error(WaClient::Error)
      Sidekiq.redis { |redis| redis.call("DEL", SendGuard::THROTTLE_KEY) }
      expect(events("mensagem_falhou").last).to include("motivo" => "erro_wa", "vai_retentar" => i < 3)
    end

    Sidekiq.redis { |redis| redis.call("SET", SendGuard::THROTTLE_KEY, "1") }
    expect { described_class.new.perform(log.id) }.to raise_error(SendGuard::ThrottledError)
    expect(events("mensagem_falhou").last).to include("motivo" => "throttle")
  end

  it "RF-18: desconectado, duplicata e limite diário não re-tentam (não levantam) e gravam o motivo (TT-04)" do
    stub_request(:post, wa_send).to_return(status: 503, body: { error: "not_connected" }.to_json)
    expect { described_class.new.perform(log.id) }.not_to raise_error
    expect(log.reload).to have_attributes(status: "failed", error_message: "wa-service não está conectado")

    MessageLog.create!(group_jid: group.jid, rendered_body: log.rendered_body, status: "sent", sent_at: 1.hour.ago)
    expect { described_class.new.perform(log.id) }.not_to raise_error

    allow(SendGuard).to receive(:check!).and_raise(SendGuard::DailyCapReachedError, "limite")
    expect { described_class.new.perform(log.id) }.not_to raise_error

    expect(events("mensagem_falhou").map { |e| e.values_at("motivo", "vai_retentar") })
      .to eq([ [ "desconectado", false ], [ "duplicata", false ], [ "limite_diario", false ] ])
  end

  it "TT-03/TT-05: envio grava mensagem_enviada e, se abre rodada, rodada_aberta com os membros cobrados" do
    lista = group.member_lists.create!(name: "Mensal")
    2.times { |i| lista.group_participants << GroupParticipant.create!(whatsapp_group: group, jid: "#{i}@lid") }
    group.group_rules.create!(kind: "attendance", settings: { "tracked_lists" => [ lista.key ] })
    log.update!(opens_round: true)
    stub_request(:post, wa_send).to_return(status: 200, body: { status: "sent", message_id: "W1" }.to_json, headers: { "Content-Type" => "application/json" })

    described_class.new.perform(log.id, [ "1@lid" ], "rotina")

    expect(events("mensagem_enviada").sole).to eq("message_log_id" => log.id, "flow_id" => nil, "whatsapp_group_id" => group.id,
                                                   "origem" => "rotina", "abre_rodada" => true, "abre_cobranca" => false,
                                                   "mencoes" => 1, "tentativa" => 1)
    expect(events("rodada_aberta").sole).to eq("rodada_id" => log.id, "whatsapp_group_id" => group.id, "membros_cobrados" => 2)
  end

  it "TT-13: falha ao gravar o evento não interrompe o envio" do
    allow(AnalyticsEvent).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "boom")
    stub_request(:post, wa_send).to_return(status: 200, body: { status: "sent", message_id: "W1" }.to_json, headers: { "Content-Type" => "application/json" })

    expect { described_class.new.perform(log.id) }.not_to raise_error
    expect(log.reload.status).to eq("sent")
  end
end
