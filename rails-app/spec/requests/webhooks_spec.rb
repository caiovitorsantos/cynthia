require "rails_helper"

RSpec.describe "Webhooks", type: :request do
  let(:params) { { kind: "reaction", message_id: "MSG1", participant_jid: "1@lid", text: "✅" } }

  it "recusa sem o token interno" do
    expect(AttendanceRecorder).not_to receive(:call)

    post "/webhooks/whatsapp", params: params, as: :json, headers: { "Authorization" => "errado" }

    expect(response).to have_http_status(:unauthorized)
  end

  it "repassa o evento para o AttendanceRecorder" do
    expect(AttendanceRecorder).to receive(:call).with(kind: "reaction", message_id: "MSG1", participant_jid: "1@lid", push_name: nil, text: "✅")

    post "/webhooks/whatsapp", params: params, as: :json, headers: { "Authorization" => ENV.fetch("INTERNAL_API_TOKEN") }

    expect(response).to have_http_status(:no_content)
  end
end
