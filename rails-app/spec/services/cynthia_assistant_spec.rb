require "rails_helper"

RSpec.describe CynthiaAssistant do
  let(:group) { WhatsappGroup.create!(jid: "g1@g.us", name: "Vôlei") }
  let(:api) { "https://api.anthropic.com/v1/messages" }

  around do |example|
    previous, ENV["ANTHROPIC_API_KEY"] = ENV["ANTHROPIC_API_KEY"], "test-key"
    example.run
  ensure
    ENV["ANTHROPIC_API_KEY"] = previous
  end

  def api_response(content, stop_reason)
    { status: 200, headers: { "Content-Type" => "application/json" },
      body: { id: "msg_#{SecureRandom.hex(4)}", type: "message", role: "assistant", model: "claude-haiku-5-5", content: content,
              stop_reason: stop_reason, stop_sequence: nil, usage: { input_tokens: 10, output_tokens: 5 } }.to_json }
  end

  let(:proposal) do
    [ { type: "thinking", thinking: "", signature: "sig-1" },
      { type: "tool_use", id: "toolu_1", name: "propose_template", input: { group_id: group.id, name: "Lembrete", body: "⏰ {{pendentes}}" } } ]
  end

  it "transforma o pedido em proposta pendente, sem salvar nada, e reenvia o pensamento intacto" do
    stub_request(:post, api).to_return(api_response(proposal, "tool_use"), api_response([ { type: "text", text: "Olha a prévia. Confirma aí." } ], "end_turn"))

    actions = described_class.new.reply("cria um lembrete", group: group, locale: "pt-BR")

    expect(actions.sole).to have_attributes(kind: "create_template", status: "pending", payload: include("name" => "Lembrete"))
    expect(group.templates).to be_empty
    expect(AssistantMessage.ordered.map(&:role)).to eq(%w[user assistant user assistant])
    expect(AssistantMessage.ordered.last.visible_text).to eq("Olha a prévia. Confirma aí.")
    expect(AssistantMessage.ordered.first.visible_text).to eq("cria um lembrete")

    second = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last.body)
    expect(second["model"]).to eq("claude-haiku-5-5")
    expect(second["messages"][1]["content"]).to include(include("type" => "thinking", "signature" => "sig-1"))
    expect(second["messages"][2]["content"].sole).to include("type" => "tool_result", "tool_use_id" => "toolu_1")
    expect(second["system"].first["text"]).to include("Always reply in Brazilian Portuguese")
  end

  it "confirmar cria o template; o desfecho vai como nota no turno seguinte" do
    stub_request(:post, api).to_return(api_response(proposal, "tool_use"), api_response([ { type: "text", text: "ok" } ], "end_turn"))
    action = described_class.new.reply("cria um lembrete", group: group).sole

    action.confirm!

    expect(action.reload.status).to eq("done")
    expect(group.templates.sole).to have_attributes(name: "Lembrete", body: "⏰ {{pendentes}}")

    stub_request(:post, api).to_return(api_response([ { type: "text", text: "Feito." } ], "end_turn"))
    described_class.new.reply("valeu", group: group)
    last_user = AssistantMessage.where(role: "user").ordered.last
    expect(last_user.content.first["text"]).to start_with("[painel] create_template ##{action.id}: done")
    expect(last_user.visible_text).to eq("valeu")
  end

  it "fluxo proposto usa o template pelo nome e passa pelas validações do painel" do
    group.templates.create!(name: "Presença", body: "{{data}}")
    action = AssistantAction.create!(kind: "create_flow", payload: {
      "group_id" => group.id, "name" => "Abrir lista", "trigger" => "schedule", "cron_expression" => "0 14 * * 2",
      "steps" => [ { "type" => "send_message", "template_name" => "Presença", "opens_round" => true } ]
    })

    action.confirm!

    expect(group.flows.sole).to have_attributes(cron_expression: "0 14 * * 2", steps: [ { "type" => "send_message", "opens_round" => "1", "template_id" => group.templates.sole.id.to_s } ])

    broken = AssistantAction.create!(kind: "create_flow", payload: { "group_id" => group.id, "name" => "X", "trigger" => "schedule", "cron_expression" => "0 9 * * *",
                                                                     "steps" => [ { "type" => "send_message", "template_name" => "Não existe" } ] })
    broken.confirm!
    expect(broken.reload).to have_attributes(status: "failed", result: include("Não existe"))
  end

  it "erros da API viram mensagem da Cynth.ia" do
    stub_request(:post, api).to_return(status: 401, headers: { "Content-Type" => "application/json" },
                                       body: { type: "error", error: { type: "authentication_error", message: "invalid x-api-key" } }.to_json)

    expect { described_class.new.reply("oi") }.to raise_error(CynthiaAssistant::Error, /não consegui pensar/)
  end
end
