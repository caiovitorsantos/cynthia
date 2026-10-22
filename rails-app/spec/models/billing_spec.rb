require "rails_helper"

RSpec.describe Billing do
  include ActiveSupport::Testing::TimeHelpers

  let(:group) { WhatsappGroup.create!(jid: "g1@g.us", name: "Vôlei", list_empty_text: "1.") }
  let!(:mensal) { group.member_lists.create!(name: "Mensal") }
  let!(:presence) { group.group_rules.create!(kind: "attendance", settings: { "tracked_lists" => [ "mensal" ] }) }
  let!(:rule) { group.group_rules.create!(kind: "billing", settings: { "charged_lists" => [ "mensal" ] }) }

  let!(:adriana) { member("1", "Adriana", mensal) }
  let!(:david) { member("2", "David Souza", mensal) }
  let!(:ellie) { member("3", "Ellie") }
  let!(:luana) { member("4", "Luana") }

  def member(number, name, *lists) = GroupParticipant.create!(whatsapp_group: group, jid: "#{number}@lid", phone_number: number, name: name, member_lists: lists)

  # Rodada de presença numa terça de setembro, com quem confirmou.
  def round(day, confirmed, guests: [])
    log = MessageLog.create!(group_jid: group.jid, status: "sent", opens_round: true, sent_at: Time.zone.local(2026, 9, day, 14), wa_message_id: "R#{day}")
    confirmed.each { |participant| Attendance::Response.create!(message_log: log, group_participant: participant, status: "confirmed") }
    guests.each { |name| Attendance::Response.create!(message_log: log, guest_name: name, status: "confirmed") }
  end

  def render(body) = TemplateRenderer.call(Template.new(body: body), {}, whatsapp_group: group.reload)

  def open_billing
    described_class.open!(rule, "2026-09")
    MessageLog.create!(group_jid: group.jid, status: "sent", opens_billing: true, sent_at: Time.current, wa_message_id: "B1",
                       rendered_body: "*INCLINO - PAGAMENTO Setembro*\n🚨 até 15/10\n\n...")
  end

  def paste(text) = described_class.handle_event(rule, { kind: "list", message_id: "X", participant_jid: "1@lid", text: text })

  def charge(participant, date: nil) = Billing::Charge.find_by!(group_participant: participant, date: date)

  before do
    round(2, [ adriana, ellie, luana ], guests: [ "Marco" ])
    round(9, [ luana ])
    round(30, [ david ])
  end

  it "abre mensalidades das listas que pagam e uma diária por dia jogado dos avulsos" do
    open_billing
    open_billing # idempotente

    charges = Billing::Charge.order(:kind, :date).map { |c| [ c.kind, c.label, c.date&.day ] }
    expect(charges).to contain_exactly(
      [ "mensal", "Adriana", nil ], [ "mensal", "David Souza", nil ],
      [ "avulso", "Ellie", 2 ], [ "avulso", "Luana", 2 ], [ "avulso", "Marco", 2 ], [ "avulso", "Luana", 9 ]
    )
  end

  it "monta a lista: pagos com 💰, devedores marcados com meses em atraso, avulsos por dia" do
    Billing::Charge.create!(whatsapp_group: group, group_participant: david, period: "2026-07", kind: "mensal")
    Billing::Charge.create!(whatsapp_group: group, group_participant: david, period: "2026-08", kind: "mensal")
    open_billing
    charge(adriana).update!(paid_at: Time.current)
    charge(luana, date: Date.new(2026, 9, 9)).update!(paid_at: Time.current)

    result = render("{{cobranca_mensais}}\n\nAVULSOS\n{{cobranca_avulsos}}\n\nFaltam: {{pendentes_pagamento}}")

    expect(result.body).to eq(<<~TEXT.chomp)
      1. Adriana 💰
      2. @2 3x

      AVULSOS
      02/09
      @3
      @4
      Marco

      09/09
      Luana 💰

      Faltam: @2 @3 @4 Marco
    TEXT
    expect(result.mentioned_jids).to eq([ "2@lid", "3@lid", "4@lid" ])
  end

  describe "lista colada" do
    before { open_billing }

    let(:pasted) do
      <<~TEXT
        INCLINO - PAGAMENTO SETEMBRO
        🚨 até 15/10

        PIX: volei@exemplo.com
        MENSAL: $45

          1. Adriana💰
          2. @~David Souza 5x 💰💰💰
          3. Fernando 💰

        AVULSOS SETEMBRO
        02/09
        Ellie 💰
        @4
        Marco 💰

        09/09
        Luana ✨
      TEXT
    end

    it "marca pago quem tem 💰, por mensalidade e por dia, e guarda nomes desconhecidos" do
      paste(pasted)

      expect([ charge(adriana), charge(david), charge(ellie, date: Date.new(2026, 9, 2)) ]).to all(be_paid)
      expect(charge(luana, date: Date.new(2026, 9, 2))).not_to be_paid
      expect(charge(luana, date: Date.new(2026, 9, 9))).not_to be_paid
      expect(Billing::Charge.find_by!(guest_name: "Marco")).to be_paid
      expect(described_class.unmatched_names(rule)).to eq([ "Fernando" ])
    end

    it "uma cópia sem o 💰 não desfaz o pagamento, e listas de outra cobrança são ignoradas" do
      paste(pasted)
      paste(pasted.gsub("💰", ""))
      expect(charge(adriana)).to be_paid

      paste(pasted.sub("SETEMBRO", "AGOSTO").sub("Luana ✨", "Luana 💰"))
      expect(charge(luana, date: Date.new(2026, 9, 9))).not_to be_paid
    end
  end

  it "o passo que abre a cobrança cria as cobranças antes de renderizar o template" do
    template = group.templates.create!(name: "Cobrança", body: "*PAGAMENTO {{mes_anterior}}*\n{{cobranca_mensais}}")
    flow = group.flows.create!(name: "Cobrar", trigger: "schedule", cron_expression: "0 9 1 * *",
                               steps: [ { "type" => "send_message", "template_id" => template.id.to_s, "opens_billing" => "1" } ])
    allow(DeliverMessageJob).to receive(:perform_in)

    travel_to(Time.zone.local(2026, 10, 1, 9)) { flow.run! }

    expect(MessageLog.last).to have_attributes(opens_billing: true, rendered_body: "*PAGAMENTO Setembro*\n1. @1\n2. @2")
  end
end
