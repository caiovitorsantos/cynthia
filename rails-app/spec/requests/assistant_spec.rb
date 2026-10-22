require "rails_helper"

RSpec.describe "Chat da Cynth.ia", type: :request do
  let(:group) { WhatsappGroup.create!(jid: "g1@g.us", name: "Vôlei") }

  before { post login_path, params: { username: ENV.fetch("ADMIN_USERNAME", "admin"), password: ENV.fetch("ADMIN_PASSWORD") } }

  it "mostra o chat no painel e avisa quando falta a chave" do
    get group_path(group)
    expect(response.body).to include('data-controller="assistant"', "no grupo Vôlei", %(name="group_id" id="group_id" value="#{group.id}"))

    get assistant_path
    expect(response.body).to include('<turbo-frame id="assistant_conversation">', "ANTHROPIC_API_KEY") unless CynthiaAssistant.available?
  end

  it "confirma e cancela propostas pelo cartão" do
    template = AssistantAction.create!(kind: "create_template", payload: { "group_id" => group.id, "name" => "Oi", "body" => "oi" })
    variable = AssistantAction.create!(kind: "set_variable", payload: { "group_id" => group.id, "name" => "pix", "value" => "x@y" })

    post confirm_assistant_action_path(template)
    expect(response.body).to include("turbo-stream", "Feito.")
    expect(group.templates.sole.name).to eq("Oi")

    post cancel_assistant_action_path(variable)
    expect(variable.reload.status).to eq("cancelled")
    expect(group.reload.variables).to be_empty
  end

  it "nova conversa apaga o histórico e descarta propostas pendentes" do
    AssistantMessage.create!(role: "user", content: [ { type: "text", text: "oi" } ])
    pending = AssistantAction.create!(kind: "set_variable", payload: { "group_id" => group.id, "name" => "a", "value" => "b" })

    delete assistant_path

    expect(AssistantMessage.count).to eq(0)
    expect(pending.reload.status).to eq("cancelled")
  end
end
