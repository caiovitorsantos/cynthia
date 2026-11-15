require "rails_helper"

RSpec.describe "Fluxos e templates do grupo", type: :request do
  let(:group) { WhatsappGroup.create!(jid: "g1@g.us", name: "Vôlei") }
  let!(:espera) { group.member_lists.create!(name: "Espera") }

  before { post login_path, params: { username: ENV.fetch("ADMIN_USERNAME", "admin"), password: ENV.fetch("ADMIN_PASSWORD") } }

  it "cria e edita template e fluxo pelos formulários e lista tudo na página do grupo" do
    get new_group_template_path(group)
    expect(response).to have_http_status(:ok)
    post group_templates_path(group), params: { template: { name: "Espera", body: "Na espera:\n{{lista:espera}}" } }
    template = group.templates.sole
    get edit_group_template_path(group, template)
    expect(response).to have_http_status(:ok)

    get new_group_flow_path(group, trigger: "command")
    expect(response.body).to include("Pôr quem mandou o comando numa lista")
    post group_flows_path(group), params: { flow: { name: "Entrar", trigger: "command", command: "!entrar", cron_expression: "0 9 * * *", timezone: "America/Sao_Paulo",
      steps: { "0" => { type: "add_to_list", list_key: "espera" }, "1" => { type: "send_message", template_id: template.id, opens_round: "0" }, "2" => { type: "" } } } }

    flow = group.flows.sole
    expect(response).to redirect_to(group_path(group, tab: "fluxos", anchor: "fluxos"))
    expect(flow).to have_attributes(command: "!entrar", cron_expression: nil, steps: [
      { "type" => "add_to_list", "list_key" => "espera" }, { "type" => "send_message", "template_id" => template.id.to_s, "opens_round" => "0" }
    ])

    get edit_group_flow_path(group, flow)
    expect(response).to have_http_status(:ok)
    patch group_flow_path(group, flow), params: { flow: { trigger: "command", command: "", steps: { "0" => { type: "clear_list", list_key: "espera" } } } }
    expect(response).to have_http_status(:unprocessable_entity)

    get group_path(group)
    expect(response.body).to include("Entrar", "!entrar", "Pôr quem mandou o comando numa lista")
  end

  it "salva os passos na ordem do formulário, mesmo com chaves fora de ordem (passos movidos)" do
    post group_flows_path(group), params: { flow: { name: "Limpar", trigger: "schedule", cron_expression: "0 9 * * 2", timezone: "America/Sao_Paulo",
      steps: { "1730000000000" => { type: "set_variable", name: "x", value: "1" }, "0" => { type: "clear_list", list_key: "espera" } } } }

    expect(group.flows.sole.steps.map { |step| step["type"] }).to eq(%w[set_variable clear_list])
  end

  it "não remove template usado por um fluxo" do
    template = group.templates.create!(name: "Oi", body: "oi")
    group.flows.create!(name: "Rotina", trigger: "schedule", cron_expression: "0 9 * * *", steps: [ { "type" => "send_message", "template_id" => template.id.to_s } ])

    delete group_template_path(group, template)

    expect(flash[:alert]).to include("Rotina")
    expect(Template.exists?(template.id)).to be(true)
  end

  it "executa o fluxo agora em segundo plano" do
    flow = group.flows.create!(name: "Limpar", trigger: "schedule", cron_expression: "0 9 * * *", steps: [ { "type" => "clear_list", "list_key" => "espera" } ])
    expect(RunFlowJob).to receive(:perform_async).with(flow.id, { "origem" => "executar_agora" })

    post run_group_flow_path(group, flow)
  end
end
