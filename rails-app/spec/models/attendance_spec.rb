require "rails_helper"

RSpec.describe Attendance do
  let(:group) { WhatsappGroup.create!(jid: "g1@g.us", name: "Vôlei", list_empty_text: "1.") }
  let!(:mensal) { group.member_lists.create!(name: "Mensal") }
  let!(:espera) { group.member_lists.create!(name: "Espera") }
  let!(:rule) { group.group_rules.create!(kind: "attendance", settings: { "tracked_lists" => [ "mensal" ] }) }
  let!(:round) { send_log("MSG1", opens_round: true) }
  let!(:caio) { member("1", "Caio", mensal) }

  def member(number, name, *lists, **attributes)
    GroupParticipant.create!(whatsapp_group: group, jid: "#{number}@lid", phone_number: number, name: name, member_lists: lists, **attributes)
  end

  def send_log(wa_message_id, opens_round: false, template: Template.new(body: "oi"))
    log = MessageLog.new(group_jid: group.jid, status: "pending", opens_round: opens_round)
    described_class.prepare_message(rule, log, template)
    log.tap(&:save!).tap { |saved| saved.mark_sent!(wa_message_id) }
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

  it "aceita resposta citando a lista e ignora texto sem emoji e comandos" do
    record("✅ vou sim", kind: "reply")
    record("que horas?", kind: "reply")
    record("❌", kind: "command")

    expect(responses.sole.status).to eq("confirmed")
  end

  it "cria o participante que ainda não foi sincronizado, fora das listas" do
    record("✅", jid: "99@lid", push_name: "Ellie")

    ellie = group.group_participants.find_by!(jid: "99@lid")
    expect(ellie).to have_attributes(name: "Ellie", phone_number: "99", member_lists: [])
    expect(responses.find_by!(group_participant: ellie).status).to eq("confirmed")
  end

  it "liga à rodada as mensagens que mostram a presença e conta reações nelas" do
    follow_up = send_log("MSG2", template: Template.new(body: "Faltam: {{pendentes}}"))
    expect(follow_up.round_id).to eq(round.id)

    record("✅", message_id: "MSG2")

    expect(responses.sole.status).to eq("confirmed")
  end

  it "ignora reações em mensagens que não são da rodada" do
    send_log("MSG3")

    record("✅", message_id: "MSG3")
    record("✅", message_id: "DESCONHECIDA")

    expect(Attendance::Response.count).to eq(0)
  end

  it "a rodada atual é a última mensagem enviada que abre rodada" do
    send_log("MSG4")
    expect(described_class.current_round(rule)).to eq(round)

    newer = send_log("MSG5", opens_round: true)
    expect(described_class.current_round(rule)).to eq(newer)
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

  describe "lista copiada e colada no grupo" do
    let!(:adriana) { member("2", "Adriana", mensal) }
    let!(:berto) { member("3", "Berto Silva", mensal, display_name: "Berto") }
    let!(:lew) { member("9", "Lew") }

    before { round.update!(rendered_body: "*PRESENÇA 21/10*\n_CONFIRMAR ATÉ ÀS 14h_\n\n1. Adriana\n2. Berto\n3. Caio\n\n*Avulsos*\n1.") }

    def paste(text, jid:) = described_class.handle_event(rule, { kind: "list", message_id: "X", participant_jid: "#{jid}@lid", push_name: nil, text: text })

    def status_of(participant) = responses.find_by(group_participant: participant)&.status

    let(:filled) do
      <<~TEXT
        PRESENÇA 21/10
        CONFIRMAR ATÉ ÀS 14h

          1. Adriana ✅
          2. Berto
          3. Caio ❌
          4. Caio F. ✅
          5. Feh ❓ 🤒

        Avulsos
         1.  Lew
         2. Pedro ✅
      TEXT
    end

    it "registra marcas das listas cobradas, avulsos (membros e convidados) e guarda nomes desconhecidos" do
      paste(filled, jid: "2")

      expect([ status_of(adriana), status_of(berto), status_of(caio), status_of(lew) ]).to eq([ "confirmed", nil, "declined", "confirmed" ])
      expect(described_class.guest_statuses(rule)).to eq("Pedro" => "confirmed")
      expect(described_class.unmatched_names(rule)).to eq([ "Caio F.", "Feh" ])

      result = TemplateRenderer.call(Template.new(body: "{{confirmados}}"), {}, whatsapp_group: group)
      expect(result.body).to eq("1. Lew\n2. Pedro")
    end

    it "uma cópia desatualizada não desfaz respostas dos outros; a própria linha muda" do
      record("✅") # Caio confirma pela reação
      paste(filled, jid: "2") # Adriana cola uma cópia antiga com Caio ❌
      expect(status_of(caio)).to eq("confirmed")

      paste(filled, jid: "1") # o próprio Caio cola com ❌
      expect(status_of(caio)).to eq("declined")
    end

    it "associa o nome desconhecido depois que o admin preenche o nome na lista" do
      paste(filled, jid: "2")
      caio.update!(display_name: "Caio F.")

      expect(described_class.unmatched_names(rule)).to eq([ "Feh" ])
      paste(filled, jid: "2")
      expect(status_of(caio)).to eq("declined") # resposta já existia: só a linha do próprio Caio muda
    end

    it "ignora listas de outra rodada e quando a leitura está desligada" do
      paste(filled.sub("21/10", "14/10"), jid: "2")
      expect(responses).to be_empty

      rule.update!(settings: rule.settings.merge("read_lists" => false))
      paste(filled, jid: "2")
      expect(responses).to be_empty
    end
  end

  describe "variáveis" do
    let!(:adriana) { member("2", "Adriana", mensal) }
    let!(:berto) { member("3", "Berto Silva", mensal, display_name: "Berto") }
    let!(:ellie) { member("4", "Ellie") }
    let!(:luana) { member("5", "Luana", espera) }

    def render(body) = TemplateRenderer.call(Template.new(body: body), {}, whatsapp_group: group)

    it "{{lista}} e {{mencoes}} sem chave usam as listas cobradas; com chave, a própria lista" do
      expect(render("{{lista}}").body).to eq("1. Adriana\n2. Berto\n3. Caio")
      expect(render("{{lista:espera}}").body).to eq("1. Luana")

      result = render("{{mencoes}}")
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

    it "usa o formato do grupo e as marcas da regra" do
      record("✅", jid: "2@lid")
      group.update!(list_style: "bullet", list_empty_text: "(ninguém)")
      rule.update!(settings: rule.settings.merge("confirmed_mark" => "👍", "pending_mark" => "⏳"))

      expect(render("{{presenca}}").body).to eq("• Adriana 👍\n• Berto ⏳\n• Caio ⏳")
      expect(render("{{confirmados}}").body).to eq("(ninguém)")
    end

    it "não oferece variáveis de listas que não existem" do
      expect { render("{{presenca:titular}}") }.to raise_error(TemplateRenderer::MissingVariableError)
    end

    it "sem a regra, só as variáveis de lista com chave existem" do
      rule.destroy!
      group.reload

      expect(render("{{lista:mensal}}").body).to eq("1. Adriana\n2. Berto\n3. Caio")
      expect { render("{{lista}}") }.to raise_error(TemplateRenderer::MissingVariableError)
      expect { render("{{presenca}}") }.to raise_error(TemplateRenderer::MissingVariableError)
    end
  end

  describe ".settings_from" do
    def params(hash) = ActionController::Parameters.new(hash)

    it "monta as listas cobradas sem o valor vazio e mantém campos ausentes de fora" do
      settings = described_class.settings_from(params(tracked_lists: [ "", "mensal", "espera" ], accept_replies: "0"))

      expect(settings).to eq("tracked_lists" => [ "mensal", "espera" ], "accept_replies" => false)
      expect(described_class.settings_from(params(read_lists: "0", extras_section: " Convidados "))).to eq("read_lists" => false, "extras_section" => "Convidados")
    end
  end

  describe "eventos (tracking-plan)" do
    def events(name) = AnalyticsEvent.where(name: name).map(&:properties)

    it "TT-06/TT-07: reação, resposta e remoção gravam presenca_registrada e presenca_desfeita" do
      record("✅")
      record("✅") # mesma resposta: não é evento novo
      record("❌", kind: "reply")
      record("")

      expect(events("presenca_registrada")).to eq([
        { "rodada_id" => round.id, "whatsapp_group_id" => group.id, "participante_id" => caio.id, "convidado" => false,
          "membro_cobrado" => true, "status" => "confirmed", "origem" => "reacao", "alterou_resposta" => false },
        { "rodada_id" => round.id, "whatsapp_group_id" => group.id, "participante_id" => caio.id, "convidado" => false,
          "membro_cobrado" => true, "status" => "declined", "origem" => "resposta", "alterou_resposta" => true }
      ])
      expect(events("presenca_desfeita")).to eq([ { "rodada_id" => round.id, "whatsapp_group_id" => group.id, "participante_id" => caio.id } ])
    end

    it "TT-06: lista colada grava origem lista; convidado só como booleano, sem nome" do
      round.update!(rendered_body: "PRESENCA 21/10\n\n1. Caio\n\nAvulsos\n1.")
      described_class.handle_event(rule, { kind: "list", message_id: "X", participant_jid: "1@lid", text: "PRESENCA 21/10\n\n1. Caio ✅\n\nAvulsos\n1. e2e-Pedro ✅" })

      expect(events("presenca_registrada").map { |e| e.values_at("origem", "convidado", "participante_id") })
        .to contain_exactly([ "lista", false, caio.id ], [ "lista", true, nil ])
      expect(AnalyticsEvent.pluck(:properties).to_json).not_to include("e2e-Pedro")
    end
  end
end
