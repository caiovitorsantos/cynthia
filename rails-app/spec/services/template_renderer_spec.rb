require "rails_helper"

RSpec.describe TemplateRenderer do
  describe ".call" do
    it "substitui as variáveis no corpo" do
      template = Template.new(body: "Olá {{nome}}, hoje é {{dia}}.")

      result = described_class.call(template, { "nome" => "Caio", "dia" => "segunda" })

      expect(result.body).to eq("Olá Caio, hoje é segunda.")
      expect(result.mentioned_jids).to eq([])
    end

    it "aceita chaves como symbol" do
      template = Template.new(body: "Olá {{nome}}!")

      result = described_class.call(template, { nome: "Caio" })

      expect(result.body).to eq("Olá Caio!")
    end

    it "levanta erro se sobrar variável não preenchida" do
      template = Template.new(body: "Olá {{nome}}, hoje é {{dia}}.")

      expect {
        described_class.call(template, { "nome" => "Caio" })
      }.to raise_error(TemplateRenderer::MissingVariableError, /dia/)
    end

    it "não escapa nada (texto puro, não HTML)" do
      template = Template.new(body: "<b>{{tag}}</b>")

      result = described_class.call(template, { "tag" => "<script>" })

      expect(result.body).to eq("<b><script></b>")
    end

    describe "menções (@{{...}})" do
      let(:group) { WhatsappGroup.create!(jid: "g1@g.us", name: "Grupo 1") }

      it "resolve por número e adiciona o jid às mentions" do
        GroupParticipant.create!(whatsapp_group: group, jid: "5511999999999@s.whatsapp.net", phone_number: "5511999999999", name: "Caio")
        template = Template.new(body: "Oi @{{5511999999999}}!")

        result = described_class.call(template, {}, whatsapp_group: group)

        expect(result.body).to eq("Oi @5511999999999!")
        expect(result.mentioned_jids).to eq([ "5511999999999@s.whatsapp.net" ])
      end

      it "resolve por nome (case-insensitive) e adiciona o jid às mentions" do
        GroupParticipant.create!(whatsapp_group: group, jid: "5511999999999@s.whatsapp.net", phone_number: "5511999999999", name: "Caio")
        template = Template.new(body: "Oi @{{caio}}!")

        result = described_class.call(template, {}, whatsapp_group: group)

        expect(result.body).to eq("Oi @5511999999999!")
        expect(result.mentioned_jids).to eq([ "5511999999999@s.whatsapp.net" ])
      end

      it "degrada (sem mention) quando o nome não é encontrado" do
        template = Template.new(body: "Oi @{{Fulano}}!")

        result = described_class.call(template, {}, whatsapp_group: group)

        expect(result.body).to eq("Oi @Fulano!")
        expect(result.mentioned_jids).to eq([])
      end

      it "degrada (sem mention) quando o nome é ambíguo" do
        GroupParticipant.create!(whatsapp_group: group, jid: "111@s.whatsapp.net", phone_number: "111", name: "Caio")
        GroupParticipant.create!(whatsapp_group: group, jid: "222@s.whatsapp.net", phone_number: "222", name: "Caio")
        template = Template.new(body: "Oi @{{Caio}}!")

        result = described_class.call(template, {}, whatsapp_group: group)

        expect(result.body).to eq("Oi @Caio!")
        expect(result.mentioned_jids).to eq([])
      end

      it "degrada quando não há whatsapp_group" do
        template = Template.new(body: "Oi @{{Caio}}!")

        result = described_class.call(template, {})

        expect(result.body).to eq("Oi @Caio!")
        expect(result.mentioned_jids).to eq([])
      end

      it "mistura menção com variáveis comuns" do
        GroupParticipant.create!(whatsapp_group: group, jid: "5511999999999@s.whatsapp.net", phone_number: "5511999999999", name: "Caio")
        template = Template.new(body: "Oi @{{Caio}}, hoje é {{dia}}.")

        result = described_class.call(template, { "dia" => "segunda" }, whatsapp_group: group)

        expect(result.body).to eq("Oi @5511999999999, hoje é segunda.")
        expect(result.mentioned_jids).to eq([ "5511999999999@s.whatsapp.net" ])
      end
    end

    describe "variáveis automáticas" do
      let(:group) { WhatsappGroup.create!(jid: "g1@g.us", name: "Grupo 1") }
      let(:now) { Time.zone.parse("2026-10-13 14:00") }

      it "preenche data e meses a partir de now" do
        template = Template.new(body: "PRESENÇA {{data}} | {{mes}} ({{mes_num}}) | PAGAMENTO {{mes_anterior}}")

        result = described_class.call(template, {}, now: now)

        expect(result.body).to eq("PRESENÇA 13/10 | Outubro (10) | PAGAMENTO Setembro")
      end

      it "mes_anterior de janeiro é dezembro" do
        result = described_class.call(Template.new(body: "{{mes_anterior}}"), {}, now: Time.zone.parse("2027-01-01"))

        expect(result.body).to eq("Dezembro")
      end

      it "lista mensais numerados em ordem alfabética, usando o nome na lista" do
        GroupParticipant.create!(whatsapp_group: group, jid: "2@s.whatsapp.net", phone_number: "2", name: "Caio Feliphe", display_name: "Caio F.", role: "mensal")
        GroupParticipant.create!(whatsapp_group: group, jid: "1@s.whatsapp.net", phone_number: "1", name: "Adriana", role: "mensal")
        GroupParticipant.create!(whatsapp_group: group, jid: "3@s.whatsapp.net", phone_number: "3", name: "Ellie", role: "avulso")
        GroupParticipant.create!(whatsapp_group: group, jid: "4@s.whatsapp.net", phone_number: "4", name: "Luana", role: "espera")

        result = described_class.call(Template.new(body: "{{lista_mensais}}\n--\n{{lista_espera}}"), {}, whatsapp_group: group)

        expect(result.body).to eq("1. Adriana\n2. Caio F.\n--\n1. Luana")
        expect(result.mentioned_jids).to eq([])
      end

      it "mencoes_mensais marca cada mensal" do
        GroupParticipant.create!(whatsapp_group: group, jid: "2@s.whatsapp.net", phone_number: "2", name: "Berto", role: "mensal")
        GroupParticipant.create!(whatsapp_group: group, jid: "1@s.whatsapp.net", phone_number: "1", name: "Adriana", role: "mensal")

        result = described_class.call(Template.new(body: "{{mencoes_mensais}}"), {}, whatsapp_group: group)

        expect(result.body).to eq("1. @1\n2. @2")
        expect(result.mentioned_jids).to eq([ "1@s.whatsapp.net", "2@s.whatsapp.net" ])
      end

      it "valor explícito sobrescreve a variável automática" do
        result = described_class.call(Template.new(body: "{{data}}"), { "data" => "amanhã" }, now: now)

        expect(result.body).to eq("amanhã")
      end
    end

    describe "variáveis de presença" do
      let(:group) { WhatsappGroup.create!(jid: "g1@g.us", name: "Vôlei") }
      let(:lista) { Template.create!(name: "Presença", body: "x", attendance: true) }
      let(:schedule) { Schedule.create!(template: lista, whatsapp_group: group, cron_expression: "0 14 * * 2") }
      let!(:round) { MessageLog.create!(schedule: schedule, group_jid: group.jid, status: "sent", sent_at: Time.current, wa_message_id: "MSG1") }
      let!(:adriana) { GroupParticipant.create!(whatsapp_group: group, jid: "1@lid", phone_number: "1", name: "Adriana", role: "mensal") }
      let!(:berto) { GroupParticipant.create!(whatsapp_group: group, jid: "2@lid", phone_number: "2", name: "Berto", role: "mensal") }
      let!(:caio) { GroupParticipant.create!(whatsapp_group: group, jid: "3@lid", phone_number: "3", name: "Caio", role: "mensal") }
      let!(:ellie) { GroupParticipant.create!(whatsapp_group: group, jid: "4@lid", phone_number: "4", name: "Ellie") }

      before do
        round.attendances.create!(group_participant: adriana, status: "confirmed")
        round.attendances.create!(group_participant: berto, status: "declined")
        round.attendances.create!(group_participant: ellie, status: "confirmed")
      end

      it "lista mensais com status, avulsos confirmados e marca pendentes" do
        template = Template.new(body: "{{presenca_mensais}}\nAvulsos\n{{presenca_avulsos}}\nFaltam: {{mencoes_pendentes}}")

        result = described_class.call(template, {}, whatsapp_group: group)

        expect(result.body).to eq("1. Adriana ✅\n2. Berto ❌\n3. Caio\nAvulsos\n1. Ellie\nFaltam: @3")
        expect(result.mentioned_jids).to eq([ "3@lid" ])
      end

      it "sem avulsos confirmados deixa a lista em branco no formato do grupo" do
        round.attendances.where(group_participant: ellie).destroy_all

        result = described_class.call(Template.new(body: "{{presenca_avulsos}}"), {}, whatsapp_group: group)

        expect(result.body).to eq("1.")
      end
    end
  end
end
