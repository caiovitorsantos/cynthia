require "rails_helper"

# Com raise_on_missing_translations, qualquer chave faltando num idioma quebra a renderização.
RSpec.describe "Idiomas do painel", type: :request do
  let(:group) { WhatsappGroup.create!(jid: "g1@g.us", name: "Vôlei") }

  before do
    mensal = group.member_lists.create!(name: "Mensal")
    GroupParticipant.create!(whatsapp_group: group, jid: "1@lid", phone_number: "1", name: "Caio", member_lists: [ mensal ])
    group.group_rules.create!(kind: "attendance", settings: { "tracked_lists" => [ "mensal" ] })
    billing = group.group_rules.create!(kind: "billing", settings: { "charged_lists" => [ "mensal" ] })
    template = group.templates.create!(name: "Presença", body: "{{presenca}}")
    group.flows.create!(name: "Rotina", trigger: "schedule", cron_expression: "0 14 * * 2", steps: [ { "type" => "send_message", "template_id" => template.id.to_s, "opens_round" => "1" } ])
    group.flows.create!(name: "Lista", trigger: "command", command: "!lista", steps: [ { "type" => "send_message", "template_id" => template.id.to_s } ])
    Billing.open!(billing, "2026-09")
    MessageLog.create!(group_jid: group.jid, status: "failed", rendered_body: "oi", error_message: "x")
    stub_request(:get, "#{ENV.fetch('WA_SERVICE_URL')}/health").to_return(status: 200, body: { status: "connected" }.to_json, headers: { "Content-Type" => "application/json" })
  end

  %w[pt-BR en es].each do |locale|
    it "renderiza as telas em #{locale}" do
      patch locale_path, params: { locale: locale }
      [ root_path, login_path ].each { |path| get(path) && expect(response).to(have_http_status(:ok)) }

      post login_path, params: { username: ENV.fetch("ADMIN_USERNAME", "admin"), password: ENV.fetch("ADMIN_PASSWORD") }
      flow = group.flows.first
      [ groups_path, group_path(group), new_group_flow_path(group), edit_group_flow_path(group, flow), new_group_template_path(group),
        edit_group_template_path(group, group.templates.first), logs_path, connection_path ].each do |path|
        get path
        expect(response).to have_http_status(:ok), "#{path} em #{locale}: #{response.status}"
      end
      expect(response.body).to include(I18n.t("connection.status.states.connected", locale: locale))
    end
  end

  it "usa o idioma do navegador quando ninguém escolheu, e o escolhido depois" do
    get root_path, headers: { "Accept-Language" => "es-AR,es;q=0.9,en;q=0.8" }
    expect(response.body).to include("se encarga de tu grupo")

    patch locale_path, params: { locale: "en" }
    get root_path, headers: { "Accept-Language" => "es-AR" }
    expect(response.body).to include("runs your group")
  end

  it "mensagens do grupo usam o idioma do grupo, e a assinatura padrão acompanha a troca" do
    expect(TemplateRenderer.call(Template.new(body: "{{mes}}"), {}, whatsapp_group: group, now: Time.zone.local(2026, 9, 1)).body).to eq("Setembro")

    group.update!(locale: "en")
    expect(TemplateRenderer.call(Template.new(body: "{{mes}}"), {}, whatsapp_group: group, now: Time.zone.local(2026, 9, 1)).body).to eq("September")
    expect(group.signature).to include("against her will")

    group.update!(signature: "_minha_", locale: "es")
    expect(group.signature).to eq("_minha_")
  end
end
