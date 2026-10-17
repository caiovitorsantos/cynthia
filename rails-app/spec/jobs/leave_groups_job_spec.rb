require "rails_helper"

RSpec.describe LeaveGroupsJob do
  let(:leave_url) { "#{ENV.fetch('WA_SERVICE_URL')}/groups/leave" }
  let!(:g1) { WhatsappGroup.create!(jid: "g1@g.us", name: "Grupo 1") }
  let!(:g2) { WhatsappGroup.create!(jid: "g2@g.us", name: "Grupo 2") }
  let!(:g3) { WhatsappGroup.create!(jid: "g3@g.us", name: "Grupo 3") }

  before { allow_any_instance_of(described_class).to receive(:sleep) }

  it "sai de cada grupo e segue em frente quando um falha" do
    stub_request(:post, leave_url).with(body: { group_jid: "g1@g.us" }.to_json).to_return(status: 200, body: "{}")
    stub_request(:post, leave_url).with(body: { group_jid: "g2@g.us" }.to_json).to_return(status: 500, body: "boom")

    described_class.new.perform([ g1.id, g2.id ])

    expect(WhatsappGroup.pluck(:name)).to contain_exactly("Grupo 2", "Grupo 3")
  end

  it "para tudo se o WhatsApp desconectar" do
    stub_request(:post, leave_url).to_return(status: 503)

    described_class.new.perform([ g1.id, g2.id ])

    expect(WebMock).to have_requested(:post, leave_url).once
    expect(WhatsappGroup.count).to eq(3)
  end
end
