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
end
