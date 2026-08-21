require "rails_helper"

RSpec.describe SendGuard do
  describe ".check!" do
    it "permite o primeiro envio e bloqueia o segundo dentro da janela de throttle" do
      expect {
        described_class.check!(group_jid: "grupo@g.us", message: "oi")
      }.not_to raise_error

      expect {
        described_class.check!(group_jid: "outro@g.us", message: "tchau")
      }.to raise_error(SendGuard::ThrottledError)
    end
  end

  describe "cap diário" do
    it "bloqueia quando o limite diário de envios já foi atingido" do
      SendGuard::MAX_DAILY_SENDS.times do |i|
        MessageLog.create!(group_jid: "g@g.us", rendered_body: "msg #{i}", status: "sent", sent_at: Time.current)
      end

      expect {
        described_class.send(:check_daily_cap!)
      }.to raise_error(SendGuard::DailyCapReachedError)
    end

    it "não bloqueia abaixo do limite" do
      expect { described_class.send(:check_daily_cap!) }.not_to raise_error
    end
  end

  describe "duplicidade" do
    it "bloqueia mensagem idêntica ao mesmo grupo dentro da janela de 6h" do
      MessageLog.create!(group_jid: "g@g.us", rendered_body: "oi", status: "sent", sent_at: 1.hour.ago)

      expect {
        described_class.send(:check_duplicate!, "g@g.us", "oi")
      }.to raise_error(SendGuard::DuplicateMessageError)
    end

    it "não bloqueia fora da janela de 6h" do
      MessageLog.create!(group_jid: "g@g.us", rendered_body: "oi", status: "sent", sent_at: 7.hours.ago)

      expect {
        described_class.send(:check_duplicate!, "g@g.us", "oi")
      }.not_to raise_error
    end

    it "não bloqueia mensagem diferente" do
      MessageLog.create!(group_jid: "g@g.us", rendered_body: "oi", status: "sent", sent_at: 1.hour.ago)

      expect {
        described_class.send(:check_duplicate!, "g@g.us", "tchau")
      }.not_to raise_error
    end
  end
end
