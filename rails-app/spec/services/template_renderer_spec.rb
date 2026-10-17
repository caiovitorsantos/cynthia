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

    describe "variáveis do grupo" do
      let(:group) { WhatsappGroup.create!(jid: "g9@g.us", name: "Vôlei", variables: { "pix" => "pix@vôlei", "local" => "Quadra 1" }) }

      it "preenche com os valores do grupo, abaixo dos valores do agendamento" do
        template = Template.new(body: "PIX {{pix}} em {{local}}", default_variables: { "local" => "padrão", "pix" => "padrão" })

        result = described_class.call(template, { "local" => "Quadra 2" }, whatsapp_group: group)

        expect(result.body).to eq("PIX pix@vôlei em Quadra 2")
      end
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

      it "@{{todos}} notifica todos os participantes sem listar os números" do
        GroupParticipant.create!(whatsapp_group: group, jid: "1@lid", phone_number: "1", name: "Ana")
        GroupParticipant.create!(whatsapp_group: group, jid: "2@lid", phone_number: "2", name: "Bia")

        result = described_class.call(Template.new(body: "Bom dia @{{todos}}!"), {}, whatsapp_group: group)

        expect(result.body).to eq("Bom dia @todos!")
        expect(result.mentioned_jids).to contain_exactly("1@lid", "2@lid")
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

      it "valor explícito sobrescreve a variável automática" do
        result = described_class.call(Template.new(body: "{{data}}"), { "data" => "amanhã" }, now: now)

        expect(result.body).to eq("amanhã")
      end
    end
  end
end
