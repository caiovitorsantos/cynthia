require "rails_helper"

RSpec.describe GroupAssistantJob do
  let(:group) { WhatsappGroup.create!(jid: "g1@g.us", name: "Vôlei") }
  let!(:caio) { GroupParticipant.create!(whatsapp_group: group, jid: "1@lid", phone_number: "1", name: "Caio", admin: true) }
  let!(:bruno) { GroupParticipant.create!(whatsapp_group: group, jid: "2@lid", phone_number: "2", name: "Bruno") }
  let(:other) { WhatsappGroup.create!(jid: "g2@g.us", name: "Outro grupo secreto") }
  let(:api) { "https://api.anthropic.com/v1/messages" }

  around do |example|
    previous, ENV["ANTHROPIC_API_KEY"] = ENV["ANTHROPIC_API_KEY"], "test-key"
    example.run
  ensure
    ENV["ANTHROPIC_API_KEY"] = previous
  end

  before do
    allow(DeliverMessageJob).to receive(:perform_async)
    Sidekiq.redis { |redis| redis.call("FLUSHDB") }
  end

  def notice_sent!(at = 1.day.ago)
    MessageLog.create!(group_jid: group.jid, kind: MessageLog::AI_NOTICE, rendered_body: "aviso", status: "sent", sent_at: at)
  end

  def wa_send = "#{ENV.fetch('WA_SERVICE_URL')}/send"

  def api_response(content, stop_reason)
    { status: 200, headers: { "Content-Type" => "application/json" },
      body: { id: "msg_1", type: "message", role: "assistant", model: "claude-haiku-5-5", content: content,
              stop_reason: stop_reason, stop_sequence: nil, usage: { input_tokens: 1, output_tokens: 1 } }.to_json }
  end

  def requests = WebMock::RequestRegistry.instance.requested_signatures.hash.keys.select { |sig| sig.uri.host == "api.anthropic.com" }.map { |sig| JSON.parse(sig.body) }

  def mention(jid, text) = described_class.new.perform(group.id, { "participant_jid" => jid, "push_name" => nil, "text" => text })

  it "responde quem não é admin só com consultas, preso ao próprio grupo, marcando quem perguntou" do
    notice_sent!
    peek = [ { type: "tool_use", id: "t1", name: "get_group", input: { group_id: other.id } } ]
    stub_request(:post, api).to_return(api_response(peek, "tool_use"), api_response([ { type: "text", text: "Ugh. Confirmaram 0." } ], "end_turn"))

    mention("2@lid", "@cynthia quem confirmou?")

    first, second = requests
    expect(first["tools"].map { |tool| tool["name"] }).to eq(%w[get_group])
    expect(first["system"].first["text"]).to include('"Vôlei"', "not a group admin")
    tool_result = second["messages"][2]["content"].sole["content"]
    expect(tool_result).to include('"name":"Vôlei"')
    expect(tool_result).not_to include("secreto")
    expect(MessageLog.last.rendered_body).to eq("@2 Ugh. Confirmaram 0.")
    expect(DeliverMessageJob).to have_received(:perform_async).with(MessageLog.last.id, [ "2@lid" ])
  end

  it "admin pede mudança: a proposta vai com a prévia completa e espera um sim" do
    notice_sent!
    proposal = [ { type: "tool_use", id: "t1", name: "propose_variable", input: { group_id: other.id, name: "pix", value: "volei@x" } } ]
    stub_request(:post, api).to_return(api_response(proposal, "tool_use"), api_response([ { type: "text", text: "Propus." } ], "end_turn"))

    mention("1@lid", "@cynthia troca o pix pra volei@x")

    action = AssistantAction.sole
    expect(action).to have_attributes(channel: "group", status: "pending", message_log: MessageLog.last)
    expect(action.payload["group_id"]).to eq(group.id)
    expect(MessageLog.last.rendered_body).to include("@1 Propus.", "{{pix}} = volei@x", "responde *sim*")
    expect(AssistantAction.panel).to be_empty
  end

  it "respeita o teto de respostas por hora do grupo" do
    notice_sent!
    stub_const("GroupAssistantJob::HOURLY_LIMIT", 1)
    stub_request(:post, api).to_return(api_response([ { type: "text", text: "oi" } ], "end_turn"))

    2.times { mention("2@lid", "@cynthia oi") }

    expect(requests.size).to eq(1)
  end

  describe "aviso de IA de terceiro (RF-28)" do
    it "TM-03: menção sem aviso não chama a API; o aviso é registrado uma vez e, se falha, nada é respondido" do
      api_stub = stub_request(:post, api)
      stub_request(:post, wa_send).to_return(status: 503)

      mention("2@lid", "@cynthia oi")

      expect(api_stub).not_to have_been_requested
      notice = MessageLog.sole
      expect(notice).to have_attributes(kind: "ai_notice", status: "failed")
      expect(notice.rendered_body).to include("Anthropic", "presença", "pagou", "nunca o telefone", "Só respondo quando me marcam")
      expect(group.ai_notice_sent_at).to be_nil
      expect(DeliverMessageJob).not_to have_received(:perform_async)
    end

    it "não manda dois avisos quando outra menção já está enviando" do
      Sidekiq.redis { |redis| redis.call("SET", "cynthia:notice:#{group.id}", "1") }
      api_stub = stub_request(:post, api)

      mention("2@lid", "@cynthia oi")

      expect(MessageLog.count).to eq(0)
      expect(api_stub).not_to have_been_requested
    end

    it "TM-04: aviso entregue segue com a resposta; a menção seguinte não reenvia o aviso" do
      wa = stub_request(:post, wa_send).to_return(status: 200, body: { message_id: "w1" }.to_json, headers: { "Content-Type" => "application/json" })
      stub_request(:post, api).to_return(api_response([ { type: "text", text: "oi" } ], "end_turn"))
      group.update!(locale: "en")

      mention("2@lid", "@cynthia oi")
      expect(group.ai_notice_sent_at).to be_present
      expect(MessageLog.find_by(kind: "ai_notice").rendered_body).to include("Anthropic", "never phone numbers")

      mention("2@lid", "@cynthia de novo")

      expect(wa).to have_been_requested.once
      expect(MessageLog.where(kind: "ai_notice").count).to eq(1)
      expect(requests.size).to eq(2)
    end

    it "sem chave, nem aviso nem resposta" do
      ENV["ANTHROPIC_API_KEY"] = nil

      mention("2@lid", "@cynthia oi")

      expect(MessageLog.count).to eq(0)
    end
  end

  describe "minimização de PII (RF-29)" do
    before do
      notice_sent!
      group.update!(variables: { "pix" => "e2e-pix@example.invalid" })
    end

    it "TM-01/TM-02: sem telefone, JID nem valor de variável no payload; {{pix}} é preenchido localmente" do
      GroupParticipant.create!(whatsapp_group: group, jid: "5511988887777@s.whatsapp.net", phone_number: "5511988887777")
      peek = [ { type: "tool_use", id: "t1", name: "get_group", input: { group_id: group.id } } ]
      stub_request(:post, api).to_return(api_response(peek, "tool_use"), api_response([ { type: "text", text: "Pix: {{pix}}" } ], "end_turn"))

      # Remetente sem nome nem push_name, citando outro participante pelo número.
      described_class.new.perform(group.id, { "participant_jid" => "5511977776666@s.whatsapp.net", "push_name" => nil,
                                              "text" => "@5511988887777 pagou? manda o pix" })

      sender = GroupParticipant.find_by(jid: "5511977776666@s.whatsapp.net")
      bodies = WebMock::RequestRegistry.instance.requested_signatures.hash.keys.select { |sig| sig.uri.host == "api.anthropic.com" }.map(&:body)
      expect(bodies.size).to eq(2)
      bodies.each do |body|
        expect(body).not_to include("5511988887777", "5511977776666", "@s.whatsapp.net", "@lid", "e2e-pix@example.invalid")
      end
      expect(bodies.first).to include("[from: Participante ##{sender.id}]")
      expect(JSON.parse(JSON.parse(bodies.last)["messages"][2]["content"].sole["content"])).to include("variable_names" => [ "pix" ])
      expect(MessageLog.last.rendered_body).to eq("@5511977776666 Pix: e2e-pix@example.invalid")
    end
  end

  it "TM-01 (S-02): push_name com o número e telefone formatado na pergunta não chegam à Anthropic" do
    notice_sent!
    stub_request(:post, api).to_return(api_response([ { type: "text", text: "ok" } ], "end_turn"))

    described_class.new.perform(group.id, { "participant_jid" => "3@lid", "push_name" => "Zé 5511977776666",
                                            "text" => "meu cel é +55 11 98888-7777" })

    body = requests.sole.to_json
    expect(body).not_to include("5511977776666", "98888-7777")
    expect(body).to include("[from: Zé [número]]")
  end

  describe "tetos (WHA-14)" do
    before do
      notice_sent!
      stub_request(:post, api).to_return(api_response([ { type: "text", text: "oi" } ], "end_turn"))
    end

    it "uma pessoa passa do teto por hora sem gastar o teto do dia" do
      stub_const("GroupAssistantJob::PERSON_HOURLY_LIMIT", 1)
      stub_const("GroupAssistantJob::DAILY_LIMIT", 2)

      3.times { mention("2@lid", "@cynthia oi") }
      mention("1@lid", "@cynthia oi")

      expect(requests.size).to eq(2)
    end

    it "o teto diário da assistente vale para todos os grupos" do
      stub_const("GroupAssistantJob::DAILY_LIMIT", 1)
      MessageLog.create!(group_jid: other.jid, kind: MessageLog::AI_NOTICE, rendered_body: "aviso", status: "sent", sent_at: 1.day.ago)
      GroupParticipant.create!(whatsapp_group: other, jid: "3@lid", phone_number: "3", name: "Ana")

      mention("2@lid", "@cynthia oi")
      described_class.new.perform(other.id, { "participant_jid" => "3@lid", "push_name" => nil, "text" => "oi" })

      expect(requests.size).to eq(1)
    end

    it "fica abaixo da cota diária do SendGuard" do
      expect(GroupAssistantJob::DAILY_LIMIT).to be < SendGuard::MAX_DAILY_SENDS
    end
  end

  it "menção sem participante não faz nada" do
    notice_sent!
    api_stub = stub_request(:post, api)

    described_class.new.perform(group.id, { "participant_jid" => "", "push_name" => nil, "text" => "oi" })

    expect(api_stub).not_to have_been_requested
  end

  it "ferramenta não oferecida (propose_* para não admin, método interno) não roda e devolve erro" do
    notice_sent!
    calls = [ { type: "tool_use", id: "t1", name: "propose_variable", input: { group_id: group.id, name: "pix", value: "golpe@x" } },
              { type: "tool_use", id: "t2", name: "list_groups", input: {} },
              { type: "tool_use", id: "t3", name: "run_tool", input: {} },
              { type: "tool_use", id: "t4", name: "instance_variable_get", input: {} } ]
    stub_request(:post, api).to_return(api_response(calls, "tool_use"), api_response([ { type: "text", text: "ok" } ], "end_turn"))

    mention("2@lid", "@cynthia troca o pix")

    expect(AssistantAction.count).to eq(0)
    results = requests.last["messages"][2]["content"]
    expect(results.map { |result| JSON.parse(result["content"]) }).to all(eq("error" => "unknown tool"))
  end
end
