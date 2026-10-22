require "rails_helper"

RSpec.describe "Groups", type: :request do
  before { post login_path, params: { username: ENV.fetch("ADMIN_USERNAME", "admin"), password: ENV.fetch("ADMIN_PASSWORD") } }

  it "salva o nome nas listas e as listas de cada participante" do
    group = WhatsappGroup.create!(jid: "g1@g.us", name: "Grupo 1")
    mensal = group.member_lists.create!(name: "Mensal")
    pagou = group.member_lists.create!(name: "Pagou")
    of_other_group = WhatsappGroup.create!(jid: "g2@g.us", name: "Grupo 2").member_lists.create!(name: "Mensal")
    participant = GroupParticipant.create!(whatsapp_group: group, jid: "1@s.whatsapp.net", phone_number: "1", name: "Caio Feliphe")

    patch group_path(group), params: { participants: { participant.id => { display_name: "Caio F.", member_list_ids: [ "", mensal.id, pagou.id, of_other_group.id ] } } }

    expect(response).to redirect_to(group_path(group, anchor: "membros"))
    expect(participant.reload.display_name).to eq("Caio F.")
    expect(participant.member_lists).to contain_exactly(mensal, pagou)

    patch group_path(group), params: { participants: { participant.id => { display_name: "", member_list_ids: [ "" ] } } }
    expect(participant.reload).to have_attributes(display_name: nil, member_lists: [])
  end

  it "cria, renomeia e apaga listas e salva o formato" do
    group = WhatsappGroup.create!(jid: "g1@g.us", name: "Grupo 1")
    mensal = group.member_lists.create!(name: "Mensal")
    espera = group.member_lists.create!(name: "Espera")

    patch lists_group_path(group), params: {
      lists: { "0" => { id: mensal.id, name: "Mensalistas" }, "1" => { id: espera.id, name: "" }, "2" => { id: "", name: "Pagou em dia" } },
      list_style: "dash", list_empty_text: "-"
    }

    expect(group.member_lists.reload.map { |list| [ list.key, list.name ] }).to contain_exactly([ "mensal", "Mensalistas" ], [ "pagou_em_dia", "Pagou em dia" ])
    expect(group.reload).to have_attributes(list_style: "dash", list_empty_text: "-")
  end

  describe "sair e remover" do
    let(:group) { WhatsappGroup.create!(jid: "g1@g.us", name: "Grupo 1") }
    before do
      template = group.templates.create!(name: "Oi", body: "oi")
      group.flows.create!(name: "Oi", trigger: "schedule", cron_expression: "0 14 * * 2", steps: [ { "type" => "send_message", "template_id" => template.id.to_s } ])
    end

    it "sai do grupo no WhatsApp e apaga o grupo, templates e fluxos" do
      stub = stub_request(:post, "#{ENV.fetch('WA_SERVICE_URL')}/groups/leave")
        .with(body: { group_jid: "g1@g.us" }.to_json)
        .to_return(status: 200, body: { status: "left" }.to_json, headers: { "Content-Type" => "application/json" })

      post leave_group_path(group)

      expect(stub).to have_been_requested
      expect(response).to redirect_to(groups_path)
      expect(WhatsappGroup.exists?(group.id)).to be(false)
      expect([ Flow.count, Template.count ]).to eq([ 0, 0 ])
    end

    it "mantém o grupo se o wa-service falhar" do
      stub_request(:post, "#{ENV.fetch('WA_SERVICE_URL')}/groups/leave").to_return(status: 503)

      post leave_group_path(group)

      expect(response).to redirect_to(group_path(group))
      expect(WhatsappGroup.exists?(group.id)).to be(true)
    end

    it "remove da lista sem chamar o wa-service" do
      delete group_path(group)

      expect(response).to redirect_to(groups_path)
      expect(WhatsappGroup.exists?(group.id)).to be(false)
    end
  end

  describe "ações em lote" do
    let!(:g1) { WhatsappGroup.create!(jid: "g1@g.us", name: "Grupo 1") }
    let!(:g2) { WhatsappGroup.create!(jid: "g2@g.us", name: "Grupo 2") }
    let!(:g3) { WhatsappGroup.create!(jid: "g3@g.us", name: "Grupo 3") }

    it "enfileira a saída dos selecionados em segundo plano" do
      expect(LeaveGroupsJob).to receive(:perform_async).with(contain_exactly(g1.id, g2.id))

      post leave_selected_groups_path, params: { ids: [ g1.id, g2.id ] }

      expect(response).to redirect_to(groups_path)
      expect(WhatsappGroup.count).to eq(3)
    end

    it "remove os selecionados da lista" do
      post destroy_selected_groups_path, params: { ids: [ g1.id, g3.id ] }

      expect(WhatsappGroup.pluck(:name)).to eq([ "Grupo 2" ])
      expect(flash[:notice]).to include("2 grupo(s)")
    end
  end

  describe "regra de presença" do
    let(:group) { WhatsappGroup.create!(jid: "g1@g.us", name: "Vôlei") }

    before do
      GroupParticipant.create!(whatsapp_group: group, jid: "1@lid", phone_number: "1", name: "Caio")
      group.member_lists.create!(name: "Titular")
    end

    it "organiza a página em abas, com membros primeiro e filtro por lista" do
      get group_path(group)

      tabs = response.body.scan(/role="tab"[^>]*>([^<]+)</).flatten
      expect(tabs).to eq([ "Membros e listas", "Fluxos", "Templates", "Variáveis", "Regras" ])
      expect(response.body).to include('data-filter-key-param="titular"', 'data-filter-key-param="-"', 'data-keys="-"')
    end

    it "sem a regra, a página não mostra a coluna de presença" do
      get group_path(group)

      expect(response.body).not_to include("Presença</th>")
      expect(response.body).to include("Ativar", "Titular")
    end

    it "ativa, configura as listas cobradas e desativa" do
      post group_rules_path(group), params: { kind: "attendance" }
      rule = group.group_rules.sole

      patch group_rule_path(group, rule), params: { rule: { tracked_lists: [ "", "titular" ], confirmed_mark: "👍" } }
      expect(Attendance.settings(rule.reload)).to include("tracked_lists" => [ "titular" ], "confirmed_mark" => "👍", "decline_emojis" => "❌ ✖ ❎ 👎")

      get group_path(group)
      expect(response.body).to include("Presença</th>", "Listas cobradas:</strong> Titular")

      delete group_rule_path(group, rule)
      expect(group.group_rules.reload).to be_empty
    end
  end

  it "mostra a cobrança e marca/desfaz pagamento pelo painel" do
    group = WhatsappGroup.create!(jid: "g9@g.us", name: "Vôlei")
    mensal = group.member_lists.create!(name: "Mensal")
    caio = GroupParticipant.create!(whatsapp_group: group, jid: "1@lid", phone_number: "1", name: "Caio", member_lists: [ mensal ])
    post group_rules_path(group), params: { kind: "billing" }
    patch group_rule_path(group, group.group_rules.sole), params: { rule: { charged_lists: [ "", "mensal" ] } }
    Billing.open!(group.group_rules.sole, "2026-09")
    charge = Billing::Charge.sole

    get group_path(group)
    expect(response.body).to include("Cobrança mensal", "Listas que pagam mensalidade:</strong> Mensal", "Setembro/2026", "Marcar pago")

    patch group_charge_path(group, charge)
    expect(charge.reload).to be_paid
    patch group_charge_path(group, charge)
    expect(charge.reload).not_to be_paid
    expect(caio.reload).to be_present
  end

  it "salva as variáveis do grupo, normaliza o nome e descarta linhas sem nome" do
    group = WhatsappGroup.create!(jid: "g7@g.us", name: "Vôlei", variables: { "antiga" => "x" })

    patch variables_group_path(group), params: { variables: {
      "0" => { name: "PIX", value: "pix@exemplo.com" },
      "1" => { name: "Valor mensal", value: "R$45" },
      "2" => { name: "", value: "ignorado" }
    }, signature: " _— Cynth.ia do vôlei_ " }

    expect(response).to redirect_to(group_path(group, anchor: "variaveis"))
    expect(group.reload.variables).to eq("pix" => "pix@exemplo.com", "valor_mensal" => "R$45")
    expect(group.signature).to eq("_— Cynth.ia do vôlei_")
  end
end
