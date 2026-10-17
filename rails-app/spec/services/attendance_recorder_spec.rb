require "rails_helper"

RSpec.describe AttendanceRecorder do
  let(:group) { WhatsappGroup.create!(jid: "g1@g.us", name: "Vôlei") }
  let(:lista) { Template.create!(name: "Presença", body: "PRESENÇA {{data}}", attendance: true) }
  let(:lembrete) { Template.create!(name: "Lembrete", body: "Faltam: {{mencoes_pendentes}}") }
  let(:round) { send_log(lista, "MSG1") }
  let!(:caio) { GroupParticipant.create!(whatsapp_group: group, jid: "1@lid", phone_number: "1", name: "Caio", role: "mensal") }

  def send_log(template, wa_message_id, round: nil)
    schedule = Schedule.create!(template: template, whatsapp_group: group, cron_expression: "0 14 * * 2")
    MessageLog.create!(schedule: schedule, group_jid: group.jid, status: "sent", sent_at: Time.current, wa_message_id: wa_message_id, round: round)
  end

  def record(text, kind: "reaction", message_id: round.wa_message_id, jid: "1@lid", push_name: nil)
    described_class.call(kind: kind, message_id: message_id, participant_jid: jid, push_name: push_name, text: text)
  end

  it "confirma com ✅ e cancela com ❌ (a última reação vale)" do
    record("✅")
    expect(round.attendances.sole).to have_attributes(group_participant: caio, status: "confirmed")

    record("❌")
    expect(round.attendances.sole.status).to eq("declined")
  end

  it "aceita variações como ✔️ e 👍🏽" do
    record("✔️")
    expect(round.attendances.sole.status).to eq("confirmed")
    record("👍🏽")
    expect(round.attendances.sole.status).to eq("confirmed")
  end

  it "apaga a resposta quando a reação é removida" do
    record("✅")
    record("")

    expect(round.attendances).to be_empty
  end

  it "aceita resposta citando a lista e ignora texto sem emoji" do
    record("✅ vou sim", kind: "reply")
    expect(round.attendances.sole.status).to eq("confirmed")

    record("que horas?", kind: "reply")
    expect(round.attendances.sole.status).to eq("confirmed")
  end

  it "cria o participante que ainda não foi sincronizado, como avulso" do
    record("✅", jid: "99@lid", push_name: "Ellie")

    ellie = group.group_participants.find_by!(jid: "99@lid")
    expect(ellie).to have_attributes(name: "Ellie", phone_number: "99", role: nil)
    expect(round.attendances.find_by!(group_participant: ellie).status).to eq("confirmed")
  end

  it "conta reação numa mensagem de acompanhamento para a rodada que ela acompanha" do
    follow_up = send_log(lembrete, "MSG2", round: round)

    record("✅", message_id: follow_up.wa_message_id)

    expect(round.attendances.sole.status).to eq("confirmed")
    expect(follow_up.attendances).to be_empty
  end

  it "ignora reações em mensagens que não são lista de presença" do
    outra = send_log(lembrete, "MSG3")

    record("✅", message_id: outra.wa_message_id)
    record("✅", message_id: "DESCONHECIDA")

    expect(Attendance.count).to eq(0)
  end
end
