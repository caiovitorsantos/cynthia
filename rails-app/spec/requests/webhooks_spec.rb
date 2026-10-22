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

  it "dispara os fluxos do comando com quem mandou e o texto" do
    group = WhatsappGroup.create!(jid: "g1@g.us", name: "Vôlei")
    list = group.member_lists.create!(name: "Espera")
    flow = group.flows.create!(name: "Entrar", trigger: "command", command: "!entrar", steps: [ { "type" => "add_to_list", "list_key" => list.key } ])
    group.flows.create!(name: "Outro", trigger: "command", command: "!sair", steps: [ { "type" => "remove_from_list", "list_key" => list.key } ])
    expect(RunFlowJob).to receive(:perform_async).once.with(flow.id, { "sender_jid" => "1@lid", "push_name" => "Caio", "text" => "!Entrar já" })

    post "/webhooks/whatsapp", params: params.merge(kind: "command", text: "!Entrar já", push_name: "Caio"), as: :json,
                               headers: { "Authorization" => ENV.fetch("INTERNAL_API_TOKEN") }

    expect(response).to have_http_status(:no_content)
  end

  it "ignora grupos sem regras" do
    WhatsappGroup.create!(jid: "g1@g.us", name: "Outro")
    expect(Attendance).not_to receive(:handle_event)

    post "/webhooks/whatsapp", params: params, as: :json, headers: { "Authorization" => ENV.fetch("INTERNAL_API_TOKEN") }

    expect(response).to have_http_status(:no_content)
  end
end
