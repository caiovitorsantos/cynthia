require "rails_helper"

RSpec.describe "Webhooks", type: :request do
  let(:params) { { kind: "reaction", group_jid: "g1@g.us", message_id: "MSG1", participant_jid: "1@lid", text: "✅" } }

  it "recusa sem o token interno" do
    expect(Attendance).not_to receive(:handle_event)

    post "/webhooks/whatsapp", params: params, as: :json, headers: { "Authorization" => "errado" }

    expect(response).to have_http_status(:unauthorized)
  end

  it "repassa o evento para as regras do grupo" do
    group = WhatsappGroup.create!(jid: "g1@g.us", name: "Vôlei")
    rule = group.group_rules.create!(kind: "attendance")
    expect(Attendance).to receive(:handle_event).with(rule, { kind: "reaction", message_id: "MSG1", participant_jid: "1@lid", push_name: nil, text: "✅" })

    post "/webhooks/whatsapp", params: params, as: :json, headers: { "Authorization" => ENV.fetch("INTERNAL_API_TOKEN") }

    expect(response).to have_http_status(:no_content)
  end

  it "ignora grupos sem regras" do
    WhatsappGroup.create!(jid: "g1@g.us", name: "Outro")
    expect(Attendance).not_to receive(:handle_event)

    post "/webhooks/whatsapp", params: params, as: :json, headers: { "Authorization" => ENV.fetch("INTERNAL_API_TOKEN") }

    expect(response).to have_http_status(:no_content)
  end
end
