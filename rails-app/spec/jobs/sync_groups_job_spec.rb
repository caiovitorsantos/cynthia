require "rails_helper"

RSpec.describe SyncGroupsJob do
  let(:wa_service_url) { ENV.fetch("WA_SERVICE_URL") }

  it "faz upsert dos grupos retornados pelo wa-service" do
    stub_request(:get, "#{wa_service_url}/groups").to_return(
      status: 200,
      body: [ { jid: "g1@g.us", name: "Grupo 1", participants_count: 3 } ].to_json,
      headers: { "Content-Type" => "application/json" }
    )

    described_class.new.perform

    group = WhatsappGroup.find_by(jid: "g1@g.us")
    expect(group.name).to eq("Grupo 1")
    expect(group.participants_count).to eq(3)
    expect(group.synced_at).to be_present
  end

  it "sincroniza os participantes retornados junto com o grupo" do
    stub_request(:get, "#{wa_service_url}/groups").to_return(
      status: 200,
      body: [
        {
          jid: "g1@g.us",
          name: "Grupo 1",
          participants_count: 2,
          participants: [
            { jid: "5511999999999@s.whatsapp.net", name: "Caio" },
            { jid: "5511888888888@s.whatsapp.net", name: nil }
          ]
        }
      ].to_json,
      headers: { "Content-Type" => "application/json" }
    )

    described_class.new.perform

    group = WhatsappGroup.find_by(jid: "g1@g.us")
    expect(group.group_participants.count).to eq(2)

    caio = group.group_participants.find_by(jid: "5511999999999@s.whatsapp.net")
    expect(caio.name).to eq("Caio")
    expect(caio.phone_number).to eq("5511999999999")
  end

  it "remove participantes que saíram do grupo numa nova sincronização" do
    stub_request(:get, "#{wa_service_url}/groups").to_return(
      status: 200,
      body: [ { jid: "g1@g.us", name: "Grupo 1", participants_count: 2, participants: [
        { jid: "a@s.whatsapp.net", name: "A" }, { jid: "b@s.whatsapp.net", name: "B" }
      ] } ].to_json,
      headers: { "Content-Type" => "application/json" }
    ).then.to_return(
      status: 200,
      body: [ { jid: "g1@g.us", name: "Grupo 1", participants_count: 1, participants: [
        { jid: "a@s.whatsapp.net", name: "A" }
      ] } ].to_json,
      headers: { "Content-Type" => "application/json" }
    )

    described_class.new.perform
    described_class.new.perform

    group = WhatsappGroup.find_by(jid: "g1@g.us")
    expect(group.group_participants.pluck(:jid)).to eq([ "a@s.whatsapp.net" ])
  end

  it "mantém participantes já sincronizados quando o wa-service não envia a chave participants" do
    group = WhatsappGroup.create!(jid: "g1@g.us", name: "Grupo 1")
    GroupParticipant.create!(whatsapp_group: group, jid: "a@s.whatsapp.net", name: "A", phone_number: "a")

    stub_request(:get, "#{wa_service_url}/groups").to_return(
      status: 200,
      body: [ { jid: "g1@g.us", name: "Grupo 1", participants_count: 1 } ].to_json,
      headers: { "Content-Type" => "application/json" }
    )

    described_class.new.perform

    expect(group.reload.group_participants.count).to eq(1)
  end
end
