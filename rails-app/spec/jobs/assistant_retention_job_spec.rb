require "rails_helper"

RSpec.describe AssistantRetentionJob do
  def turn(role, type, at) = AssistantMessage.create!(role: role, content: [ { type: type } ], created_at: at)

  it "TM-11: apaga turnos e propostas com mais de 30 dias, sem deixar tool_result órfão no começo" do
    old = 31.days.ago
    turn("user", "text", old)
    use = turn("assistant", "tool_use", 30.days.ago - 1.minute)
    result = turn("user", "tool_result", 29.days.ago) # par do tool_use antigo: não pode abrir a conversa
    answer = turn("assistant", "text", 29.days.ago)
    question = turn("user", "text", 1.day.ago)
    reply = turn("assistant", "text", 1.day.ago)
    old_action = AssistantAction.create!(kind: "set_variable", payload: {}, created_at: old)
    new_action = AssistantAction.create!(kind: "set_variable", payload: {})

    described_class.new.perform

    expect(AssistantMessage.ordered.ids).to eq([ question.id, reply.id ])
    expect(AssistantMessage.where(id: [ use.id, result.id, answer.id ])).to be_empty
    expect(AssistantAction.ids).to eq([ new_action.id ])
    expect(old_action.class.exists?(old_action.id)).to be(false)
  end

  it "sem turno de usuário com texto no prazo, a conversa antiga toda sai" do
    turn("user", "text", 40.days.ago)
    turn("assistant", "text", 40.days.ago)

    described_class.new.perform

    expect(AssistantMessage.count).to eq(0)
  end

  it "TM-11: o histórico enviado à API tem no máximo HISTORY_LIMIT turnos e começa num turno do usuário com texto" do
    stub_const("AssistantMessage::HISTORY_LIMIT", 4)
    turn("user", "text", 1.hour.ago)
    turn("assistant", "tool_use", 1.hour.ago)
    turn("user", "tool_result", 1.hour.ago) # cairia no começo do corte de 4: pulado
    turn("assistant", "text", 1.hour.ago)
    question = turn("user", "text", 1.minute.ago)
    turn("assistant", "text", 1.minute.ago)

    history = AssistantMessage.history
    expect(history.size).to eq(2)
    expect(history.first[:content]).to eq(question.content)
  end
end
