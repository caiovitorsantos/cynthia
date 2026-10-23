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

  def api_response(content, stop_reason)
    { status: 200, headers: { "Content-Type" => "application/json" },
      body: { id: "msg_1", type: "message", role: "assistant", model: "claude-haiku-5-5", content: content,
              stop_reason: stop_reason, stop_sequence: nil, usage: { input_tokens: 1, output_tokens: 1 } }.to_json }
  end

  def requests = WebMock::RequestRegistry.instance.requested_signatures.hash.keys.map { |signature| JSON.parse(signature.body) }

  def mention(jid, text) = described_class.new.perform(group.id, { "participant_jid" => jid, "push_name" => nil, "text" => text })

  it "responde quem não é admin só com consultas, preso ao próprio grupo, marcando quem perguntou" do
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
    stub_const("GroupAssistantJob::HOURLY_LIMIT", 1)
    stub_request(:post, api).to_return(api_response([ { type: "text", text: "oi" } ], "end_turn"))

    2.times { mention("2@lid", "@cynthia oi") }

    expect(requests.size).to eq(1)
  end
end
