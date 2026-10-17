require "rails_helper"

RSpec.describe Attendance do
  let(:group) { WhatsappGroup.create!(jid: "g1@g.us", name: "Vôlei") }
  let(:lista) { Template.create!(name: "Presença", body: "PRESENÇA {{data}}") }
  let(:lembrete) { Template.create!(name: "Lembrete", body: "Faltam: {{pendentes}}") }
  let!(:rule) { group.group_rules.create!(kind: "attendance", template_id: lista.id) }
  let!(:round) { send_log(lista, "MSG1") }
  let!(:caio) { GroupParticipant.create!(whatsapp_group: group, jid: "1@lid", phone_number: "1", name: "Caio", role: "mensal") }

  def send_log(template, wa_message_id)
    schedule = Schedule.create!(template: template, whatsapp_group: group, cron_expression: "0 14 * * 2")
    MessageLog.create!(schedule: schedule, group_jid: group.jid, status: "pending").tap { |log| log.mark_sent!(wa_message_id) }
  end

  def record(text, kind: "reaction", message_id: "MSG1", jid: "1@lid", push_name: nil)
    described_class.handle_event(rule, { kind: kind, message_id: message_id, participant_jid: jid, push_name: push_name, text: text })
  end

  def responses = Attendance::Response.where(message_log: round)

  it "confirma com ✅ e cancela com ❌ (a última reação vale)" do
    record("✅")
    expect(responses.sole).to have_attributes(group_participant: caio, status: "confirmed")

    record("❌")
    expect(responses.sole.status).to eq("declined")
  end

  it "aceita variações como ✔️ e 👍🏽" do
    record("✔️")
    expect(responses.sole.status).to eq("confirmed")
    record("👍🏽")
    expect(responses.sole.status).to eq("confirmed")
  end

  it "apaga a resposta quando a reação é removida" do
    record("✅")
    record("")

    expect(responses).to be_empty
  end

  it "aceita resposta citando a lista e ignora texto sem emoji" do
    record("✅ vou sim", kind: "reply")
    record("que horas?", kind: "reply")

    expect(responses.sole.status).to eq("confirmed")
  end

  it "cria o participante que ainda não foi sincronizado, como avulso" do
    record("✅", jid: "99@lid", push_name: "Ellie")

    ellie = group.group_participants.find_by!(jid: "99@lid")
    expect(ellie).to have_attributes(name: "Ellie", phone_number: "99", role: nil)
    expect(responses.find_by!(group_participant: ellie).status).to eq("confirmed")
  end

  it "liga o lembrete à rodada e conta reações nele para ela" do
    follow_up = send_log(lembrete, "MSG2")
    expect(follow_up.reload.round_id).to eq(round.id)

    record("✅", message_id: "MSG2")

    expect(responses.sole.status).to eq("confirmed")
  end

  it "ignora reações em mensagens que não são da rodada" do
    send_log(Template.create!(name: "Aviso", body: "oi"), "MSG3")

    record("✅", message_id: "MSG3")
    record("✅", message_id: "DESCONHECIDA")

    expect(Attendance::Response.count).to eq(0)
  end

  it "só o template configurado na regra abre rodada" do
    expect(described_class.current_round(rule)).to eq(round)

    rule.update!(template_id: lembrete.id)

    expect(described_class.current_round(rule)).to be_nil
  end

  it "sincronização que apaga o participante leva as respostas junto" do
    record("✅")

    group.group_participants.where(id: caio.id).delete_all

    expect(Attendance::Response.count).to eq(0)
  end

  it "respeita emojis configurados e pode ignorar respostas por texto" do
    rule.update!(settings: rule.settings.merge("confirm_emojis" => "🏐", "decline_emojis" => "🚫", "accept_replies" => false))

    record("✅")
    expect(responses).to be_empty

    record("🏐")
    expect(responses.sole.status).to eq("confirmed")

    record("🚫 hoje não", kind: "reply")
    expect(responses.sole.status).to eq("confirmed")
  end

  describe "variáveis" do
    let!(:adriana) { GroupParticipant.create!(whatsapp_group: group, jid: "2@lid", phone_number: "2", name: "Adriana", role: "mensal") }
    let!(:berto) { GroupParticipant.create!(whatsapp_group: group, jid: "3@lid", phone_number: "3", name: "Berto Silva", display_name: "Berto", role: "mensal") }
    let!(:ellie) { GroupParticipant.create!(whatsapp_group: group, jid: "4@lid", phone_number: "4", name: "Ellie") }
    let!(:luana) { GroupParticipant.create!(whatsapp_group: group, jid: "5@lid", phone_number: "5", name: "Luana", role: "espera") }

    def render(body) = TemplateRenderer.call(Template.new(body: body), {}, whatsapp_group: group)

    it "sem categoria usa as fixas; com categoria, só ela" do
      expect(render("{{lista}}").body).to eq("1. Adriana\n2. Berto\n3. Caio")
      expect(render("{{lista:espera}}").body).to eq("1. Luana")

      result = render("{{mencoes:mensal}}")
      expect(result.body).to eq("1. @2\n2. @3\n3. @1")
      expect(result.mentioned_jids).to eq([ "2@lid", "3@lid", "1@lid" ])
    end

    it "mostra a presença da rodada atual e marca quem falta" do
      record("✅", jid: "2@lid")
      record("❌", jid: "3@lid")
      record("✅", jid: "4@lid")
      record("✅", jid: "5@lid")

      result = render("{{presenca}}\nAvulsos\n{{confirmados}}\nEspera: {{confirmados:espera}}\nFaltam: {{pendentes}}")

      expect(result.body).to eq("1. Adriana ✅\n2. Berto ❌\n3. Caio\nAvulsos\n1. Ellie\n2. Luana\nEspera: 1. Luana\nFaltam: @1")
      expect(result.mentioned_jids).to eq([ "1@lid" ])
    end

    it "usa o formato configurado" do
      record("✅", jid: "2@lid")
      rule.update!(settings: rule.settings.merge("list_style" => "bullet", "confirmed_mark" => "👍", "pending_mark" => "⏳", "empty_text" => "(ninguém)"))

      expect(render("{{presenca}}").body).to eq("• Adriana 👍\n• Berto ⏳\n• Caio ⏳")
      expect(render("{{confirmados}}").body).to eq("(ninguém)")
    end

    it "categorias configuradas pelo grupo" do
      rule.update!(settings: rule.settings.merge("categories" => [ { "key" => "titular", "name" => "Titular", "fixed" => true } ]))
      adriana.update!(role: "titular")

      expect(render("{{lista}}").body).to eq("1. Adriana")
      expect(render("{{lista:titular}}").body).to eq("1. Adriana")
      expect { render("{{lista:mensal}}") }.to raise_error(TemplateRenderer::MissingVariableError)
    end

    it "não existem em grupos sem a regra" do
      other = WhatsappGroup.create!(jid: "g2@g.us", name: "Outro")

      expect {
        TemplateRenderer.call(Template.new(body: "{{lista}}"), {}, whatsapp_group: other)
      }.to raise_error(TemplateRenderer::MissingVariableError)
    end
  end

  describe ".settings_from" do
    def params(hash) = ActionController::Parameters.new(hash)

    it "monta categorias, gera chave pelo nome, ignora linhas sem nome e mantém campos ausentes de fora" do
      settings = described_class.settings_from(params(
        categories: {
          "0" => { key: "mensal", name: "Mensalista", fixed: "1" },
          "1" => { key: "", name: "Convidado VIP", fixed: "0" },
          "2" => { key: "", name: "", fixed: "0" }
        },
        accept_replies: "0"
      ))

      expect(settings).to eq(
        "categories" => [
          { "key" => "mensal", "name" => "Mensalista", "fixed" => true },
          { "key" => "convidado_vip", "name" => "Convidado VIP", "fixed" => false }
        ],
        "accept_replies" => false
      )
    end
  end
end
