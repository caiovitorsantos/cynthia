require "rails_helper"

RSpec.describe AnalyticsEvent do
  it "só aceita os 12 eventos do tracking-plan" do
    expect(described_class.track(:inventado)).to be_nil
    expect(described_class.track(:admin_logado)).to be_persisted
  end

  it "TT-13: recusa propriedade que parece PII (telefone, JID, e-mail, texto longo) e não levanta" do
    [ "5511988887777", "1@lid", "e2e-pix@example.invalid", "x" * 33, { nested: 1 } ].each do |value|
      expect(described_class.track(:admin_logado, valor: value)).to be_nil
    end
    expect(described_class.count).to eq(0)
  end

  it "TT-13: falha ao gravar dentro de uma transação não aborta a transação de quem chamou" do
    allow(described_class).to receive(:create!) { described_class.connection.execute("SELECT 1/0") } # erro do Postgres
    group = nil
    ActiveRecord::Base.transaction do
      expect(described_class.track(:admin_logado)).to be_nil
      group = WhatsappGroup.create!(jid: "g1@g.us", name: "ok")
    end

    expect(group).to be_persisted
  end
end
