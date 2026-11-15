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
    expect(RunFlowJob).to receive(:perform_async).once.with(flow.id, { "sender_jid" => "1@lid", "push_name" => "Caio", "text" => "!Entrar já", "origem" => "comando" })

    post "/webhooks/whatsapp", params: params.merge(kind: "command", text: "!Entrar já", push_name: "Caio"), as: :json,
                               headers: { "Authorization" => ENV.fetch("INTERNAL_API_TOKEN") }

    expect(response).to have_http_status(:no_content)
  end

  describe "grupo com Cynth.ia" do
    let(:group) { WhatsappGroup.create!(jid: "g1@g.us", name: "Vôlei") }
    let(:token) { { "Authorization" => ENV.fetch("INTERNAL_API_TOKEN") } }
    let!(:admin) { GroupParticipant.create!(whatsapp_group: group, jid: "9@lid", phone_number: "9", admin: true) }

    def send_event(kind, text, jid: "1@lid", message_id: "MSG1")
      post "/webhooks/whatsapp", params: params.merge(kind: kind, text: text, participant_jid: jid, message_id: message_id), as: :json, headers: token
    end

    it "menção vira resposta dela em segundo plano" do
      group
      expect(GroupAssistantJob).to receive(:perform_async).with(group.id, include("text" => "@cynthia oi", "participant_jid" => "1@lid"))

      send_event("mention", "@cynthia oi")
    end

    it "comandos que mexem em dados só rodam para admin; os de consulta, para todos" do
      list = group.member_lists.create!(name: "Espera")
      pix = group.flows.create!(name: "Pix", trigger: "command", command: "!pix", steps: [ { "type" => "set_variable", "name" => "pix", "value" => "{{argumento}}" } ])
      group.flows.create!(name: "Entrar", trigger: "command", command: "!espera", steps: [ { "type" => "add_to_list", "list_key" => list.key } ])
      allow(DeliverMessageJob).to receive(:perform_async)
      allow(RunFlowJob).to receive(:perform_async)

      send_event("command", "!pix golpe@x")
      expect(RunFlowJob).not_to have_received(:perform_async)
      expect(MessageLog.last.rendered_body).to eq("!pix é só pra admin. Ugh.")

      send_event("command", "!pix volei@x", jid: "9@lid")
      expect(RunFlowJob).to have_received(:perform_async).with(pix.id, anything).once

      send_event("command", "!espera")
      expect(RunFlowJob).to have_received(:perform_async).twice
    end

    it "sim de admin citando a proposta confirma e responde; de outra pessoa não faz nada" do
      log = MessageLog.create!(group_jid: group.jid, status: "sent", wa_message_id: "PROP1", rendered_body: "proposta")
      action = AssistantAction.create!(kind: "set_variable", channel: "group", message_log: log, payload: { "group_id" => group.id, "name" => "pix", "value" => "v@x" })
      allow(DeliverMessageJob).to receive(:perform_async)
      expect(Attendance).not_to receive(:handle_event)
      group.group_rules.create!(kind: "attendance")

      send_event("reply", "sim", message_id: "PROP1")
      expect(action.reload.status).to eq("pending")

      send_event("reply", "Sim!", jid: "9@lid", message_id: "PROP1")
      expect(action.reload.status).to eq("done")
      expect(group.reload.variables).to eq("pix" => "v@x")
      expect(MessageLog.last.rendered_body).to eq("Feito: variável {{pix}}. De nada.")
    end

    it "TM-08: sim de admin a uma proposta com mais de 1 h não executa (T5)" do
      log = MessageLog.create!(group_jid: group.jid, status: "sent", wa_message_id: "PROP2", rendered_body: "proposta", created_at: 61.minutes.ago)
      action = AssistantAction.create!(kind: "set_variable", channel: "group", message_log: log, payload: { "group_id" => group.id, "name" => "pix", "value" => "v@x" })
      allow(DeliverMessageJob).to receive(:perform_async)

      send_event("reply", "sim", jid: "9@lid", message_id: "PROP2")

      expect(action.reload.status).to eq("cancelled")
      expect(group.reload.variables).to be_empty
    end
  end

  it "ignora grupos sem regras" do
    WhatsappGroup.create!(jid: "g1@g.us", name: "Outro")
    expect(Attendance).not_to receive(:handle_event)

    post "/webhooks/whatsapp", params: params, as: :json, headers: { "Authorization" => ENV.fetch("INTERNAL_API_TOKEN") }

    expect(response).to have_http_status(:no_content)
  end

  describe "S-07 e sessão" do
    let(:token) { { "Authorization" => ENV.fetch("INTERNAL_API_TOKEN") } }
    let(:group) { WhatsappGroup.create!(jid: "g1@g.us", name: "Vôlei") }
    let!(:pix) { group.flows.create!(name: "Pix", trigger: "command", command: "!pix", steps: [ { "type" => "set_variable", "name" => "pix", "value" => "x" } ]) }

    before { allow(DeliverMessageJob).to receive(:perform_async) }

    it "S-07: comando sem participante só vale como admin com from_me explícito" do
      allow(RunFlowJob).to receive(:perform_async)
      event = params.merge(kind: "command", text: "!pix", participant_jid: "")

      post "/webhooks/whatsapp", params: event, as: :json, headers: token
      expect(RunFlowJob).not_to have_received(:perform_async)
      expect(MessageLog.last.rendered_body).to include("só pra admin")

      post "/webhooks/whatsapp", params: event.merge(from_me: true), as: :json, headers: token
      expect(RunFlowJob).to have_received(:perform_async).with(pix.id, include("origem" => "comando")).once
    end

    it "TT-11/TT-12: eventos de sessão do wa-service viram analytics_events, só com as propriedades numéricas" do
      post "/webhooks/whatsapp", params: { kind: "session", event: "sessao_caiu", codigo: 428, logout: false, extra: "5511988887777" }, as: :json, headers: token
      post "/webhooks/whatsapp", params: { kind: "session", event: "sessao_conectada", apos_queda_s: 3 }, as: :json, headers: token
      post "/webhooks/whatsapp", params: { kind: "session", event: "drop_table" }, as: :json, headers: token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(AnalyticsEvent.order(:id).map { |e| [ e.name, e.properties ] })
        .to eq([ [ "sessao_caiu", { "codigo" => 428, "logout" => false } ], [ "sessao_conectada", { "apos_queda_s" => 3 } ] ])
    end

    it "sessão sem token: 401 e nada gravado" do
      post "/webhooks/whatsapp", params: { kind: "session", event: "sessao_caiu" }, as: :json, headers: { "Authorization" => "errado" }

      expect(response).to have_http_status(:unauthorized)
      expect(AnalyticsEvent.count).to eq(0)
    end
  end
end
