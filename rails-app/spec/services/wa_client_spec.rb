require "rails_helper"

RSpec.describe WaClient do
  let(:base_url) { ENV.fetch("WA_SERVICE_URL") }

  describe ".status" do
    it "retorna o status reportado pelo wa-service" do
      stub_request(:get, "#{base_url}/health").to_return(
        status: 200, body: { status: "connected", connected: true }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      expect(described_class.status).to eq("connected")
    end
  end

  describe ".send_message" do
    it "levanta NotConnected quando o wa-service responde 503" do
      stub_request(:post, "#{base_url}/send").to_return(status: 503, body: { error: "not_connected" }.to_json)

      expect {
        described_class.send_message(group_jid: "g@g.us", message: "oi")
      }.to raise_error(WaClient::NotConnected)
    end

    it "levanta Error genérico para outros status de falha" do
      stub_request(:post, "#{base_url}/send").to_return(status: 500, body: "boom")

      expect {
        described_class.send_message(group_jid: "g@g.us", message: "oi")
      }.to raise_error(WaClient::Error)
    end
  end
end
