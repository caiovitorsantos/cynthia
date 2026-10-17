require "rails_helper"

RSpec.describe "Groups", type: :request do
  before { post login_path, params: { username: ENV.fetch("ADMIN_USERNAME", "admin"), password: ENV.fetch("ADMIN_PASSWORD") } }

  it "salva tipo e nome na lista dos participantes" do
    group = WhatsappGroup.create!(jid: "g1@g.us", name: "Grupo 1")
    participant = GroupParticipant.create!(whatsapp_group: group, jid: "1@s.whatsapp.net", phone_number: "1", name: "Caio Feliphe")

    patch group_path(group), params: { participants: { participant.id => { role: "mensal", display_name: "Caio F." } } }

    expect(response).to redirect_to(group_path(group))
    expect(participant.reload).to have_attributes(role: "mensal", display_name: "Caio F.")
  end

  describe "sair e remover" do
    let(:group) { WhatsappGroup.create!(jid: "g1@g.us", name: "Grupo 1") }
    let(:template) { Template.create!(name: "Oi", body: "oi") }

    before { Schedule.create!(template: template, whatsapp_group: group, cron_expression: "0 14 * * 2") }

    it "sai do grupo no WhatsApp e apaga o grupo e seus agendamentos" do
      stub = stub_request(:post, "#{ENV.fetch('WA_SERVICE_URL')}/groups/leave")
        .with(body: { group_jid: "g1@g.us" }.to_json)
        .to_return(status: 200, body: { status: "left" }.to_json, headers: { "Content-Type" => "application/json" })

      post leave_group_path(group)

      expect(stub).to have_been_requested
      expect(response).to redirect_to(groups_path)
      expect(WhatsappGroup.exists?(group.id)).to be(false)
      expect(Schedule.count).to eq(0)
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
end
