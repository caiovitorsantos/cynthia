require "rails_helper"

RSpec.describe Flow do
  let(:group) { WhatsappGroup.create!(jid: "g1@g.us", name: "Vôlei", list_empty_text: "(ninguém)") }
  let!(:espera) { group.member_lists.create!(name: "Espera") }
  let(:aviso) { group.templates.create!(name: "Aviso", body: "Espera:\n{{lista:espera}}") }

  def step(type, **fields) = { "type" => type }.merge(fields.stringify_keys)

  def command_flow(*steps) = group.flows.create!(name: "Entrar", trigger: "command", command: "!entrar", steps: steps)

  describe "validações" do
    it "exige cron ou data, não os dois, num fluxo de horário" do
      flow = group.flows.new(name: "x", trigger: "schedule", steps: [ step("send_message", template_id: aviso.id.to_s) ])
      expect(flow).not_to be_valid

      flow.cron_expression = "0 9 * * 1"
      expect(flow).to be_valid
      expect(flow.tap(&:save!).next_run_at).to be_present
    end

    it "exige comando começando com ! e guarda em minúsculas" do
      flow = group.flows.new(name: "x", trigger: "command", command: "lista", steps: [ step("clear_list", list_key: "espera") ])
      expect(flow).not_to be_valid

      flow.command = " !Lista "
      expect(flow).to be_valid
      expect(flow.command).to eq("!lista")
    end

    it "recusa passos de remetente em rotinas, listas inexistentes e variáveis sem valor" do
      sem_valor = group.templates.create!(name: "Pix", body: "Pague em {{pix}}")
      flow = group.flows.new(name: "x", trigger: "schedule", cron_expression: "0 9 * * 1", steps: [
        step("add_to_list", list_key: "espera"),
        step("clear_list", list_key: "nao_existe"),
        step("send_message", template_id: sem_valor.id.to_s)
      ])

      expect(flow).not_to be_valid
      expect(flow.errors[:steps].join).to include("só funciona com gatilho de comando", "escolha a lista", "usa variáveis sem valor: pix")
    end

    it "aceita {{remetente}} em fluxos de comando e variáveis definidas por um passo anterior" do
      template = group.templates.create!(name: "Pix", body: "{{remetente}}: {{pix}}")
      flow = group.flows.new(name: "x", trigger: "command", command: "!pix", steps: [
        step("set_variable", name: "pix", value: "{{argumento}}"),
        step("send_message", template_id: template.id.to_s)
      ])

      expect(flow).to be_valid
    end
  end

  it ".steps_from guarda só os campos do tipo e descarta linhas sem tipo" do
    steps = described_class.steps_from(ActionController::Parameters.new(
      "0" => { type: "set_variable", name: "Chave Pix", value: " x ", list_key: "espera" },
      "1" => { type: "", template_id: "1" }
    ).permit!)

    expect(steps).to eq([ { "type" => "set_variable", "name" => "chave_pix", "value" => "x" } ])
  end

  describe "#run!" do
    let(:context) { { "sender_jid" => "9@lid", "push_name" => "Ellie", "text" => "!entrar agora" } }

    it "põe quem mandou o comando na lista e envia o template já com a lista atualizada" do
      flow = command_flow(step("add_to_list", list_key: "espera"), step("send_message", template_id: aviso.id.to_s, opens_round: "0"))
      expect(DeliverMessageJob).to receive(:perform_in).twice.with(0, kind_of(Integer), [])

      flow.run!(context)
      flow.run!(context) # repetido não duplica

      ellie = group.group_participants.find_by!(jid: "9@lid")
      expect(espera.group_participants).to eq([ ellie ])
      expect(MessageLog.last).to have_attributes(flow: flow, rendered_body: "Espera:\n1. Ellie", opens_round: false)
    end

    it "espaça mensagens seguidas pela janela do SendGuard e marca a que abre rodada" do
      flow = command_flow(step("send_message", template_id: aviso.id.to_s, opens_round: "1"), step("send_message", template_id: aviso.id.to_s))
      expect(DeliverMessageJob).to receive(:perform_in).with(0, anything, anything).ordered
      expect(DeliverMessageJob).to receive(:perform_in).with(SendGuard::THROTTLE_WINDOW + 1, anything, anything).ordered

      flow.run!(context)

      expect(MessageLog.order(:id).pluck(:opens_round)).to eq([ true, false ])
    end

    it "tira da lista, esvazia a lista e define variável com o argumento" do
      espera.group_participants << GroupParticipant.create!(whatsapp_group: group, jid: "9@lid", phone_number: "9")
      espera.group_participants << GroupParticipant.create!(whatsapp_group: group, jid: "8@lid", phone_number: "8")

      command_flow(step("remove_from_list", list_key: "espera"), step("set_variable", name: "quem", value: "{{remetente}} disse {{argumento}}")).run!(context)
      expect(espera.group_participants.pluck(:jid)).to eq([ "8@lid" ])
      expect(group.reload.variables).to eq("quem" => "9 disse agora")

      command_flow(step("clear_list", list_key: "espera")).run!(context)
      expect(espera.reload.group_participants).to be_empty
    end

    it "pula passos de remetente quando o comando vem sem remetente (execução manual)" do
      flow = command_flow(step("add_to_list", list_key: "espera"))

      flow.run!

      expect(espera.group_participants).to be_empty
    end
  end

  describe "RunDueFlowsJob" do
    it "dispara as rotinas vencidas e calcula a próxima execução" do
      flow = group.flows.create!(name: "x", trigger: "schedule", cron_expression: "0 9 * * *", steps: [ step("send_message", template_id: aviso.id.to_s) ])
      once = group.flows.create!(name: "y", trigger: "schedule", run_at: 1.hour.from_now, steps: [ step("send_message", template_id: aviso.id.to_s) ])
      flow.update_columns(next_run_at: 1.minute.ago)
      once.update_columns(next_run_at: 1.minute.ago)
      expect(RunFlowJob).to receive(:perform_async).with(flow.id)
      expect(RunFlowJob).to receive(:perform_async).with(once.id)

      RunDueFlowsJob.new.perform

      expect(flow.reload.next_run_at).to be > Time.current
      expect(once.reload).to have_attributes(next_run_at: nil, active: true)
      expect(once.last_run_at).to be_present
    end
  end
end
