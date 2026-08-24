require "rails_helper"

RSpec.describe GroupParticipant do
  let(:group) { WhatsappGroup.create!(jid: "g1@g.us", name: "Grupo 1") }

  it "é válido com jid e grupo" do
    participant = GroupParticipant.new(whatsapp_group: group, jid: "5511999999999@s.whatsapp.net", name: "Caio")

    expect(participant).to be_valid
  end

  it "exige jid" do
    participant = GroupParticipant.new(whatsapp_group: group, jid: nil)

    expect(participant).not_to be_valid
    expect(participant.errors[:jid]).to be_present
  end

  it "não permite jid duplicado no mesmo grupo" do
    GroupParticipant.create!(whatsapp_group: group, jid: "5511999999999@s.whatsapp.net")
    dup = GroupParticipant.new(whatsapp_group: group, jid: "5511999999999@s.whatsapp.net")

    expect(dup).not_to be_valid
  end

  it "permite o mesmo jid em grupos diferentes" do
    other_group = WhatsappGroup.create!(jid: "g2@g.us", name: "Grupo 2")
    GroupParticipant.create!(whatsapp_group: group, jid: "5511999999999@s.whatsapp.net")
    same_jid_other_group = GroupParticipant.new(whatsapp_group: other_group, jid: "5511999999999@s.whatsapp.net")

    expect(same_jid_other_group).to be_valid
  end
end
