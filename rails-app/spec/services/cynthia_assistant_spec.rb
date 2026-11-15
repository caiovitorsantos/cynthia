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

  it "com um grupo aberto, recusa propor ações em outro grupo e marca os dados do grupo como não confiáveis" do
    other = WhatsappGroup.create!(jid: "g2@g.us", name: "Outro")
    elsewhere = [ { type: "tool_use", id: "toolu_2", name: "propose_variable", input: { group_id: other.id, name: "pix", value: "golpe@x" } } ]
    stub_request(:post, api).to_return(api_response(elsewhere, "tool_use"), api_response([ { type: "text", text: "ok" } ], "end_turn"))

    expect(described_class.new.reply("oi", group: group)).to be_empty
    expect(AssistantAction.count).to eq(0)
    expect(AssistantMessage.where(role: "user").ordered.last.content.sole["content"]).to include("only the open group")

    expect(described_class.new.send(:get_group, { "group_id" => group.id })[:note]).to include("untrusted")
  end

  it "envia o workspace quando a chave não é de um workspace" do
    ENV["ANTHROPIC_WORKSPACE_ID"] = "wrkspc_teste"
    stub = stub_request(:post, api).with(headers: { "anthropic-workspace-id" => "wrkspc_teste" }).to_return(api_response([ { type: "text", text: "ok" } ], "end_turn"))

    described_class.new.reply("oi")

    expect(stub).to have_been_requested
  ensure
    ENV.delete("ANTHROPIC_WORKSPACE_ID")
  end

  it "erros da API viram mensagem da Cynth.ia" do
    stub_request(:post, api).to_return(status: 401, headers: { "Content-Type" => "application/json" },
                                       body: { type: "error", error: { type: "authentication_error", message: "invalid x-api-key" } }.to_json)

    expect { described_class.new.reply("oi") }.to raise_error(CynthiaAssistant::Error, /não consegui pensar/)
  end

  it "no grupo, não admin não cria proposta mesmo que a ferramenta esteja na lista (RF-26)" do
    assistant = described_class.new(client: nil)
    assistant.instance_variable_set(:@group, group)
    assistant.instance_variable_set(:@channel, "group")
    assistant.instance_variable_set(:@sender_admin, false)

    output, action = assistant.send(:run_tool, "propose_variable", { "name" => "pix", "value" => "x" }, %w[propose_variable])

    expect(output).to eq(error: "only group admins can propose changes")
    expect(action).to be_nil
    expect(AssistantAction.count).to eq(0)
  end

  it "TM-01 no painel: get_group leva só nomes e nomes de variáveis, um grupo, até 150 participantes" do
    group.update!(variables: { "pix" => "e2e-pix@example.invalid" })
    GroupParticipant.create!(whatsapp_group: group, jid: "5511988887777@s.whatsapp.net", phone_number: "5511988887777")
    159.times { |i| GroupParticipant.create!(whatsapp_group: group, jid: "#{i}@lid", name: "P#{i}") }
    WhatsappGroup.create!(jid: "g2@g.us", name: "Outro grupo")
    peek = [ { type: "tool_use", id: "t1", name: "get_group", input: { group_id: group.id } } ]
    stub_request(:post, api).to_return(api_response(peek, "tool_use"), api_response([ { type: "text", text: "ok" } ], "end_turn"))

    described_class.new.reply("me liga no 5511988887777 ou 5511988887777@s.whatsapp.net", group: group)

    bodies = WebMock::RequestRegistry.instance.requested_signatures.hash.keys.map(&:body)
    bodies.each { |body| expect(body).not_to include("5511988887777", "@s.whatsapp.net", "@lid", "e2e-pix@example.invalid") }
    result = JSON.parse(JSON.parse(bodies.last)["messages"][2]["content"].sole["content"])
    expect(result["members"].size).to eq(150)
    expect(result["variable_names"]).to eq([ "pix" ])
    expect(result["name"]).to eq("Vôlei")
    expect(bodies.last).not_to include("Outro grupo")
  end

  it "TM-01 (S-02): telefone formatado e CPF na pergunta, num template e no nome do grupo viram [número]; cron, data e valor ficam" do
    group.update!(name: "Vôlei 5511977776666")
    group.templates.create!(name: "Pix", body: "Pix: +55 11 98888-7777 ou CPF 123.456.789-00, toda terça 0 14 * * 2, 21/10, R$ 1.234,56")
    peek = [ { type: "tool_use", id: "t1", name: "get_group", input: { group_id: group.id } } ]
    stub_request(:post, api).to_return(api_response(peek, "tool_use"), api_response([ { type: "text", text: "ok" } ], "end_turn"))

    described_class.new.reply("liga (11) 98888-7777 ou +55 11 98888-7777", group: group)

    bodies = WebMock::RequestRegistry.instance.requested_signatures.hash.keys.map(&:body)
    bodies.each { |body| expect(body).not_to include("98888-7777", "123.456.789-00", "5511977776666") }
    expect(bodies.last).to include("0 14 * * 2", "21/10", "R$ 1.234,56", "[número]")
  end

  it "TM-01 (RF-29): telefone logo após @ (menção a quem não é participante) vira @[número]" do
    expect(described_class.new.send(:redact, "@5511988887777 oi")).to eq("@[número] oi")
  end

  it "TM-01 (S-01): a migração apaga o histórico gravado antes da redação, e a próxima chamada não leva o telefone" do
    require Rails.root.join("db/migrate/20261031140000_reset_assistant_history_for_rf29")
    AssistantMessage.create!(role: "user", content: [ { type: "text", text: "oi" } ])
    AssistantMessage.create!(role: "assistant", content: [ { type: "text", text: "label 5511988887777, pix segredo-pix@x" } ])
    stub_request(:post, api).to_return(api_response([ { type: "text", text: "ok" } ], "end_turn"))

    ActiveRecord::Migration.suppress_messages { ResetAssistantHistoryForRf29.new.up }
    described_class.new.reply("e agora?")

    expect(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.sole.body).not_to include("5511988887777", "segredo-pix@x")
  end
end
