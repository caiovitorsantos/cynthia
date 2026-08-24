require "rails_helper"

RSpec.describe SendScheduledMessageJob do
  let(:template) { Template.create!(name: "T1", body: "Olá {{nome}}") }
  let(:group) { WhatsappGroup.create!(jid: "grupo@g.us", name: "Grupo") }
  let(:wa_service_url) { ENV.fetch("WA_SERVICE_URL") }
  let(:schedule) do
    Schedule.create!(template: template, whatsapp_group: group, run_at: 1.minute.ago, variables: { "nome" => "Caio" })
  end

  describe "quando o envio tem sucesso" do
    before do
      stub_request(:post, "#{wa_service_url}/send")
        .to_return(status: 200, body: { status: "sent" }.to_json, headers: { "Content-Type" => "application/json" })
    end

    it "cria um log 'sent' e não reagenda o one-off" do
      described_class.new.perform(schedule.id)

      log = MessageLog.last
      expect(log.status).to eq("sent")
      expect(log.group_jid).to eq(group.jid)
      expect(log.rendered_body).to eq("Olá Caio")

      expect(schedule.reload.next_run_at).to be_nil
      expect(schedule.reload.last_run_at).to be_present
    end
  end

  describe "quando o wa-service está desconectado (503)" do
    before do
      stub_request(:post, "#{wa_service_url}/send")
        .to_return(status: 503, body: { error: "not_connected" }.to_json)
    end

    it "marca o log como failed e NÃO levanta exceção (sem retry do Sidekiq)" do
      expect { described_class.new.perform(schedule.id) }.not_to raise_error

      log = MessageLog.last
      expect(log.status).to eq("failed")
      expect(log.error_message).to match(/não está conectado/)
    end
  end

  describe "quando falta variável (template editado após o schedule já existir)" do
    it "levanta erro antes de criar o MessageLog" do
      schedule # garante que o schedule já foi criado (e validado) com o corpo original
      template.update_column(:body, "Olá {{nome}}, hoje é {{dia}}")

      expect {
        described_class.new.perform(schedule.id)
      }.to raise_error(TemplateRenderer::MissingVariableError)

      expect(MessageLog.count).to eq(0)
    end
  end

  describe "quando o template tem uma menção resolvida" do
    let(:template) { Template.create!(name: "T-mention", body: "Oi @{{Caio}}, tudo bem?") }

    before do
      GroupParticipant.create!(whatsapp_group: group, jid: "5511999999999@s.whatsapp.net", phone_number: "5511999999999", name: "Caio")
      stub_request(:post, "#{wa_service_url}/send")
        .with(body: hash_including("mentions" => [ "5511999999999@s.whatsapp.net" ]))
        .to_return(status: 200, body: { status: "sent" }.to_json)
    end

    it "envia com o jid nas mentions e renderiza @numero no corpo" do
      described_class.new.perform(schedule.id)

      log = MessageLog.last
      expect(log.status).to eq("sent")
      expect(log.rendered_body).to eq("Oi @5511999999999, tudo bem?")
    end
  end

  describe "quando o throttle está ativo" do
    before do
      stub_request(:post, "#{wa_service_url}/send")
        .to_return(status: 200, body: { status: "sent" }.to_json)
      SendGuard.send(:acquire_throttle!)
    end

    it "levanta ThrottledError (permite retry do Sidekiq) e loga failed" do
      expect { described_class.new.perform(schedule.id) }.to raise_error(SendGuard::ThrottledError)

      expect(MessageLog.last.status).to eq("failed")
    end
  end
end
