# Menção de participantes em mensagens de grupo — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permitir que `Template`s marquem (`@mencionar`) participantes de um grupo do WhatsApp usando `@{{nome}}` ou `@{{numero}}` no corpo da mensagem, resolvendo para menções reais via Baileys.

**Architecture:** Uma nova tabela `group_participants` (populada pelo `SyncGroupsJob` a partir de um `GET /groups` enriquecido) guarda `jid`/`phone_number`/`name` por grupo. `TemplateRenderer` resolve tokens `@{{...}}` contra essa tabela e devolve, além do corpo renderizado, a lista de JIDs a mencionar. `WaClient`/`wa-service` propagam essa lista até `sock.sendMessage(jid, { text, mentions })` do Baileys. `wa-service` também passa a escutar eventos `contacts.upsert`/`contacts.update` do Baileys para saber os nomes dos participantes.

**Tech Stack:** Ruby on Rails 8.1 + RSpec + Sidekiq (rails-app/), Node.js + TypeScript + Express + Baileys (wa-service/).

**Spec:** `docs/superpowers/specs/2026-08-24-group-mentions-design.md`

## Global Constraints

- Comandos Ruby/RSpec rodam a partir de `rails-app/` (`bundle exec rspec ...`, `bin/rails ...`).
- Comandos do wa-service rodam a partir de `wa-service/` (`npm run build`, etc).
- Timestamp de migration segue o padrão já usado (`YYYYMMDDHHMMSS`); a próxima é `20260824120000`.
- Fallback de menção não encontrada/ambígua: mantém o texto literal (`@nome`), não menciona ninguém, loga aviso — **nunca falha o envio** (decisão da spec).
- `wa-service` não tem test runner configurado (`npm test` é um stub) — não introduzir infraestrutura de teste nova lá; verificar mudanças com `npm run build` (typecheck via `tsc`) e checagem manual. Isso é uma decisão explícita da spec, não uma lacuna do plano.
- `rails-app` não tem specs de controller/view hoje (`GroupsController` não tem nenhum) — a tarefa de UI segue esse padrão e não introduz esse tipo de teste.

---

### Task 1: Tabela e model `GroupParticipant`

**Files:**
- Create: `rails-app/db/migrate/20260824120000_create_group_participants.rb`
- Create: `rails-app/app/models/group_participant.rb`
- Modify: `rails-app/app/models/whatsapp_group.rb`
- Test: `rails-app/spec/models/group_participant_spec.rb`

**Interfaces:**
- Produces: `GroupParticipant` (colunas: `whatsapp_group_id`, `jid`, `phone_number`, `name`, `synced_at`), `belongs_to :whatsapp_group`. `WhatsappGroup#group_participants` (association).

- [ ] **Step 1: Escrever o spec (falhando)**

```ruby
# rails-app/spec/models/group_participant_spec.rb
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
```

- [ ] **Step 2: Rodar o spec e confirmar que falha**

Run: `cd rails-app && bundle exec rspec spec/models/group_participant_spec.rb`
Expected: FAIL com `NameError: uninitialized constant GroupParticipant`

- [ ] **Step 3: Criar a migration**

```ruby
# rails-app/db/migrate/20260824120000_create_group_participants.rb
class CreateGroupParticipants < ActiveRecord::Migration[8.1]
  def change
    create_table :group_participants do |t|
      t.references :whatsapp_group, null: false, foreign_key: true
      t.string   :jid, null: false
      t.string   :phone_number
      t.string   :name
      t.datetime :synced_at

      t.timestamps
    end

    add_index :group_participants, [ :whatsapp_group_id, :jid ], unique: true
  end
end
```

- [ ] **Step 4: Rodar a migration**

Run: `cd rails-app && bin/rails db:migrate`
Expected: migration aplicada, `db/schema.rb` atualizado com a tabela `group_participants`.

- [ ] **Step 5: Criar o model `GroupParticipant`**

```ruby
# rails-app/app/models/group_participant.rb
class GroupParticipant < ApplicationRecord
  belongs_to :whatsapp_group

  validates :jid, presence: true, uniqueness: { scope: :whatsapp_group_id }
end
```

- [ ] **Step 6: Adicionar a associação em `WhatsappGroup`**

```ruby
# rails-app/app/models/whatsapp_group.rb
class WhatsappGroup < ApplicationRecord
  has_many :schedules, dependent: :restrict_with_error
  has_many :group_participants, dependent: :destroy

  validates :jid, presence: true, uniqueness: true
end
```

- [ ] **Step 7: Rodar o spec de novo e confirmar que passa**

Run: `cd rails-app && bundle exec rspec spec/models/group_participant_spec.rb`
Expected: PASS (4 exemplos)

- [ ] **Step 8: Commit**

```bash
cd rails-app
git add db/migrate/20260824120000_create_group_participants.rb db/schema.rb \
  app/models/group_participant.rb app/models/whatsapp_group.rb \
  spec/models/group_participant_spec.rb
git commit -m "Adiciona tabela e model GroupParticipant"
```

---

### Task 2: `Template::VARIABLE_PATTERN` não deve capturar tokens de menção

**Contexto:** `@{{nome}}` usa a mesma sintaxe `{{...}}` das variáveis comuns. Sem esse ajuste, `Template#variable_names` (usado pela validação `Schedule#template_variables_present` e pelo preview em JS) trataria `nome` de `@{{nome}}` como uma variável comum obrigatória — o que forçaria o autor do schedule a preencher um valor fake para ela, quebrando a feature de menção.

**Files:**
- Modify: `rails-app/app/models/template.rb:2`
- Modify: `rails-app/app/javascript/controllers/template_preview_controller.js:5`
- Test: `rails-app/spec/models/template_spec.rb`

**Interfaces:**
- Produces: `Template::VARIABLE_PATTERN` (regex atualizada) e `Template#variable_names` (agora ignora tokens `@{{...}}`).

- [ ] **Step 1: Escrever o spec (falhando)**

```ruby
# rails-app/spec/models/template_spec.rb
require "rails_helper"

RSpec.describe Template do
  describe "#variable_names" do
    it "detecta variáveis comuns" do
      template = Template.new(body: "Olá {{nome}}, hoje é {{dia}}.")

      expect(template.variable_names).to contain_exactly("nome", "dia")
    end

    it "ignora tokens de menção (@{{...}})" do
      template = Template.new(body: "Oi @{{Caio}}, olha {{aviso}}.")

      expect(template.variable_names).to contain_exactly("aviso")
    end
  end
end
```

- [ ] **Step 2: Rodar o spec e confirmar que falha**

Run: `cd rails-app && bundle exec rspec spec/models/template_spec.rb`
Expected: FAIL no segundo exemplo — `variable_names` retorna `["Caio", "aviso"]` em vez de `["aviso"]`.

- [ ] **Step 3: Ajustar a regex em `Template`**

```ruby
# rails-app/app/models/template.rb
class Template < ApplicationRecord
  VARIABLE_PATTERN = /(?<!@)\{\{(\w+)\}\}/
  ...
```

(muda apenas a constante `VARIABLE_PATTERN`; o resto do arquivo continua igual)

- [ ] **Step 4: Rodar o spec e confirmar que passa**

Run: `cd rails-app && bundle exec rspec spec/models/template_spec.rb`
Expected: PASS (2 exemplos)

- [ ] **Step 5: Espelhar a mesma regra no preview em JS**

```javascript
// rails-app/app/javascript/controllers/template_preview_controller.js
import { Controller } from "@hotwired/stimulus"

// Extrai {{variaveis}} do corpo do template ao vivo, espelhando
// Template::VARIABLE_PATTERN (app/models/template.rb) em JS.
const VARIABLE_PATTERN = /(?<!@)\{\{(\w+)\}\}/g

export default class extends Controller {
  static targets = ["body", "output"]

  connect() {
    this.update()
  }

  update() {
    const matches = [...this.bodyTarget.value.matchAll(VARIABLE_PATTERN)]
    const names = [...new Set(matches.map((match) => match[1]))]

    this.outputTarget.textContent = names.length > 0 ? names.join(", ") : "nenhuma variável detectada"
  }
}
```

(só a linha da constante `VARIABLE_PATTERN` muda)

- [ ] **Step 6: Verificação manual do JS (sem test runner no projeto Rails)**

Abrir `bin/dev` (ou `bin/rails server`), ir em Templates → Novo template, digitar `Oi @{{Caio}}, olha {{aviso}}` no campo corpo, confirmar que "Variáveis detectadas" mostra só `aviso`.

- [ ] **Step 7: Commit**

```bash
cd rails-app
git add app/models/template.rb app/javascript/controllers/template_preview_controller.js \
  spec/models/template_spec.rb
git commit -m "Exclui tokens de menção (@{{...}}) da detecção de variáveis de template"
```

---

### Task 3: `WaClient.send_message` aceita `mentions`

**Files:**
- Modify: `rails-app/app/services/wa_client.rb:11-17`
- Test: `rails-app/spec/services/wa_client_spec.rb`

**Interfaces:**
- Consumes: nada de tasks anteriores.
- Produces: `WaClient.send_message(group_jid:, message:, mentions: [])` — inclui `mentions` no payload JSON só quando não vazio (mudança aditiva, não quebra chamadas existentes sem `mentions:`).

- [ ] **Step 1: Escrever os specs (falhando)**

```ruby
# rails-app/spec/services/wa_client_spec.rb — adicionar dentro de describe ".send_message"
it "inclui mentions no payload quando presente" do
  stub = stub_request(:post, "#{base_url}/send")
    .with(body: hash_including("mentions" => [ "5511999999999@s.whatsapp.net" ]))
    .to_return(status: 200, body: { status: "sent" }.to_json)

  described_class.send_message(group_jid: "g@g.us", message: "oi", mentions: [ "5511999999999@s.whatsapp.net" ])

  expect(stub).to have_been_requested
end

it "não inclui a chave mentions quando não informado" do
  stub = stub_request(:post, "#{base_url}/send")
    .with { |req| !JSON.parse(req.body).key?("mentions") }
    .to_return(status: 200, body: { status: "sent" }.to_json)

  described_class.send_message(group_jid: "g@g.us", message: "oi")

  expect(stub).to have_been_requested
end
```

(arquivo final fica com `describe ".status"` igual, e `describe ".send_message"` com os 2 exemplos existentes + esses 2 novos)

- [ ] **Step 2: Rodar os specs e confirmar que falham**

Run: `cd rails-app && bundle exec rspec spec/services/wa_client_spec.rb`
Expected: FAIL — `ArgumentError: unknown keyword: :mentions` no primeiro novo exemplo; o segundo passa incidentalmente (já não tem a chave), mas roda depois da mudança para confirmar que continua passando.

- [ ] **Step 3: Implementar**

```ruby
# rails-app/app/services/wa_client.rb
class WaClient
  Error = Class.new(StandardError)
  NotConnected = Class.new(Error)

  TIMEOUT = 15
  SEND_TIMEOUT = 30

  class << self
    def send_message(group_jid:, message:, mentions: [])
      payload = { group_jid: group_jid, message: message }
      payload[:mentions] = mentions if mentions.present?

      response = connection.post("/send", payload) do |req|
        req.options.timeout = SEND_TIMEOUT
        req.options.open_timeout = SEND_TIMEOUT
      end
      handle(response)
    end

    def groups
      handle(connection.get("/groups"))
    end

    def status
      handle(connection.get("/health"))["status"]
    end

    def qr_code
      handle(connection.get("/qr"))["qr"]
    end

    def logout
      handle(connection.post("/logout"))
    end

    private

    def connection
      Faraday.new(url: ENV.fetch("WA_SERVICE_URL")) do |f|
        f.request :json
        f.response :json
        f.headers["Authorization"] = ENV["INTERNAL_API_TOKEN"]
        f.options.timeout = TIMEOUT
        f.options.open_timeout = TIMEOUT
        f.adapter Faraday.default_adapter
      end
    end

    def handle(response)
      raise NotConnected, "wa-service não está conectado" if response.status == 503
      raise Error, "wa-service respondeu #{response.status}: #{response.body}" unless response.success?

      response.body
    end
  end
end
```

- [ ] **Step 4: Rodar os specs e confirmar que passam**

Run: `cd rails-app && bundle exec rspec spec/services/wa_client_spec.rb`
Expected: PASS (4 exemplos)

- [ ] **Step 5: Commit**

```bash
cd rails-app
git add app/services/wa_client.rb spec/services/wa_client_spec.rb
git commit -m "WaClient.send_message aceita mentions opcional"
```

---

### Task 4: `TemplateRenderer` resolve menções + `SendScheduledMessageJob` usa o resultado

**Contexto:** Mudança de interface de `TemplateRenderer.call` (passa a devolver um `Result` com `body` e `mentioned_jids` em vez de uma `String`). O único caller hoje é `SendScheduledMessageJob`, então essa tarefa atualiza os dois juntos — depois dela a suíte inteira volta a ficar verde.

**Files:**
- Modify: `rails-app/app/services/template_renderer.rb`
- Modify: `rails-app/app/jobs/send_scheduled_message_job.rb:9,14,20`
- Test: `rails-app/spec/services/template_renderer_spec.rb`
- Test: `rails-app/spec/jobs/send_scheduled_message_job_spec.rb`

**Interfaces:**
- Consumes: `GroupParticipant`/`WhatsappGroup#group_participants` (Task 1), `Template::VARIABLE_PATTERN` já ajustada (Task 2), `WaClient.send_message(..., mentions:)` (Task 3).
- Produces: `TemplateRenderer::Result` (`Struct.new(:body, :mentioned_jids)`), `TemplateRenderer.call(template, variables, whatsapp_group: nil)`.

- [ ] **Step 1: Reescrever `spec/services/template_renderer_spec.rb` (falhando)**

```ruby
# rails-app/spec/services/template_renderer_spec.rb
require "rails_helper"

RSpec.describe TemplateRenderer do
  describe ".call" do
    it "substitui as variáveis no corpo" do
      template = Template.new(body: "Olá {{nome}}, hoje é {{dia}}.")

      result = described_class.call(template, { "nome" => "Caio", "dia" => "segunda" })

      expect(result.body).to eq("Olá Caio, hoje é segunda.")
      expect(result.mentioned_jids).to eq([])
    end

    it "aceita chaves como symbol" do
      template = Template.new(body: "Olá {{nome}}!")

      result = described_class.call(template, { nome: "Caio" })

      expect(result.body).to eq("Olá Caio!")
    end

    it "levanta erro se sobrar variável não preenchida" do
      template = Template.new(body: "Olá {{nome}}, hoje é {{dia}}.")

      expect {
        described_class.call(template, { "nome" => "Caio" })
      }.to raise_error(TemplateRenderer::MissingVariableError, /dia/)
    end

    it "não escapa nada (texto puro, não HTML)" do
      template = Template.new(body: "<b>{{tag}}</b>")

      result = described_class.call(template, { "tag" => "<script>" })

      expect(result.body).to eq("<b><script></b>")
    end

    describe "menções (@{{...}})" do
      let(:group) { WhatsappGroup.create!(jid: "g1@g.us", name: "Grupo 1") }

      it "resolve por número e adiciona o jid às mentions" do
        GroupParticipant.create!(whatsapp_group: group, jid: "5511999999999@s.whatsapp.net", phone_number: "5511999999999", name: "Caio")
        template = Template.new(body: "Oi @{{5511999999999}}!")

        result = described_class.call(template, {}, whatsapp_group: group)

        expect(result.body).to eq("Oi @5511999999999!")
        expect(result.mentioned_jids).to eq([ "5511999999999@s.whatsapp.net" ])
      end

      it "resolve por nome (case-insensitive) e adiciona o jid às mentions" do
        GroupParticipant.create!(whatsapp_group: group, jid: "5511999999999@s.whatsapp.net", phone_number: "5511999999999", name: "Caio")
        template = Template.new(body: "Oi @{{caio}}!")

        result = described_class.call(template, {}, whatsapp_group: group)

        expect(result.body).to eq("Oi @5511999999999!")
        expect(result.mentioned_jids).to eq([ "5511999999999@s.whatsapp.net" ])
      end

      it "degrada (sem mention) quando o nome não é encontrado" do
        template = Template.new(body: "Oi @{{Fulano}}!")

        result = described_class.call(template, {}, whatsapp_group: group)

        expect(result.body).to eq("Oi @Fulano!")
        expect(result.mentioned_jids).to eq([])
      end

      it "degrada (sem mention) quando o nome é ambíguo" do
        GroupParticipant.create!(whatsapp_group: group, jid: "111@s.whatsapp.net", phone_number: "111", name: "Caio")
        GroupParticipant.create!(whatsapp_group: group, jid: "222@s.whatsapp.net", phone_number: "222", name: "Caio")
        template = Template.new(body: "Oi @{{Caio}}!")

        result = described_class.call(template, {}, whatsapp_group: group)

        expect(result.body).to eq("Oi @Caio!")
        expect(result.mentioned_jids).to eq([])
      end

      it "degrada quando não há whatsapp_group" do
        template = Template.new(body: "Oi @{{Caio}}!")

        result = described_class.call(template, {})

        expect(result.body).to eq("Oi @Caio!")
        expect(result.mentioned_jids).to eq([])
      end

      it "mistura menção com variáveis comuns" do
        GroupParticipant.create!(whatsapp_group: group, jid: "5511999999999@s.whatsapp.net", phone_number: "5511999999999", name: "Caio")
        template = Template.new(body: "Oi @{{Caio}}, hoje é {{dia}}.")

        result = described_class.call(template, { "dia" => "segunda" }, whatsapp_group: group)

        expect(result.body).to eq("Oi @5511999999999, hoje é segunda.")
        expect(result.mentioned_jids).to eq([ "5511999999999@s.whatsapp.net" ])
      end
    end
  end
end
```

- [ ] **Step 2: Rodar o spec e confirmar que falha**

Run: `cd rails-app && bundle exec rspec spec/services/template_renderer_spec.rb`
Expected: FAIL — `NoMethodError: undefined method 'body' for an instance of String` nos primeiros exemplos.

- [ ] **Step 3: Implementar `TemplateRenderer`**

```ruby
# rails-app/app/services/template_renderer.rb
class TemplateRenderer
  MissingVariableError = Class.new(StandardError)

  Result = Struct.new(:body, :mentioned_jids)

  MENTION_PATTERN = /@\{\{([^{}]+)\}\}/

  class << self
    def call(template, variables, whatsapp_group: nil)
      variables = variables.to_h.stringify_keys
      mentioned_jids = []

      body = template.body.gsub(MENTION_PATTERN) do
        key = Regexp.last_match(1).strip
        participant = resolve_mention(key, whatsapp_group)

        if participant
          mentioned_jids << participant.jid
          "@#{participant.phone_number}"
        else
          Rails.logger.warn("TemplateRenderer: menção não resolvida para \"#{key}\" (template ##{template.id.inspect})")
          "@#{key}"
        end
      end

      body = body.gsub(Template::VARIABLE_PATTERN) do
        key = Regexp.last_match(1)
        variables.fetch(key) { raise MissingVariableError, "Variável não preenchida: #{key}" }
      end

      Result.new(body, mentioned_jids)
    end

    private

    def resolve_mention(key, whatsapp_group)
      return nil unless whatsapp_group

      if key.match?(/\A[\d\s()+-]+\z/)
        digits = key.gsub(/\D/, "")
        whatsapp_group.group_participants.find_by(phone_number: digits)
      else
        matches = whatsapp_group.group_participants.where("LOWER(name) = ?", key.downcase).to_a
        matches.size == 1 ? matches.first : nil
      end
    end
  end
end
```

- [ ] **Step 4: Rodar o spec e confirmar que passa**

Run: `cd rails-app && bundle exec rspec spec/services/template_renderer_spec.rb`
Expected: PASS (10 exemplos)

- [ ] **Step 5: Adicionar cenário de menção em `spec/jobs/send_scheduled_message_job_spec.rb`**

```ruby
# rails-app/spec/jobs/send_scheduled_message_job_spec.rb — adicionar como novo describe,
# no mesmo nível de "quando o envio tem sucesso" etc.
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
```

(esse `describe` usa os `let(:group)` e `let(:schedule)` já definidos no topo do arquivo — `schedule` referencia `template:`, que fica sobrescrito pelo `let(:template)` local deste bloco)

- [ ] **Step 6: Rodar o spec do job e confirmar que o novo cenário falha**

Run: `cd rails-app && bundle exec rspec spec/jobs/send_scheduled_message_job_spec.rb`
Expected: FAIL no novo exemplo — `WaClient.send_message` ainda não recebe `mentions:` nenhum, o stub com `mentions` não é satisfeito.

- [ ] **Step 7: Atualizar `SendScheduledMessageJob`**

```ruby
# rails-app/app/jobs/send_scheduled_message_job.rb
class SendScheduledMessageJob
  include Sidekiq::Job

  sidekiq_options retry: 3

  def perform(schedule_id)
    schedule = Schedule.find(schedule_id)
    variables = schedule.template.default_variables.merge(schedule.variables)
    result = TemplateRenderer.call(schedule.template, variables, whatsapp_group: schedule.whatsapp_group)

    message_log = MessageLog.create!(
      schedule: schedule,
      group_jid: schedule.whatsapp_group.jid,
      rendered_body: result.body,
      status: "pending"
    )

    begin
      SendGuard.check!(group_jid: schedule.whatsapp_group.jid, message: result.body)
      WaClient.send_message(group_jid: schedule.whatsapp_group.jid, message: result.body, mentions: result.mentioned_jids)
      message_log.update!(status: "sent", sent_at: Time.current)
    rescue WaClient::NotConnected => e
      message_log.update!(status: "failed", error_message: e.message)
    rescue SendGuard::DailyCapReachedError, SendGuard::DuplicateMessageError => e
      message_log.update!(status: "failed", error_message: e.message)
    rescue SendGuard::ThrottledError, WaClient::Error => e
      message_log.update!(status: "failed", error_message: e.message)
      raise
    end

    reschedule(schedule)
  end

  private

  def reschedule(schedule)
    schedule.update!(last_run_at: Time.current)

    next_run_at = ScheduleCalculator.next_run(schedule)
    schedule.update!(next_run_at: next_run_at)
    schedule.update!(active: false) if schedule.cron_expression.present? && next_run_at.nil?
  end
end
```

- [ ] **Step 8: Rodar a suíte inteira e confirmar que passa**

Run: `cd rails-app && bundle exec rspec spec/jobs/send_scheduled_message_job_spec.rb spec/services/template_renderer_spec.rb`
Expected: PASS (todos os exemplos, incluindo os 4 cenários pré-existentes do job)

- [ ] **Step 9: Commit**

```bash
cd rails-app
git add app/services/template_renderer.rb app/jobs/send_scheduled_message_job.rb \
  spec/services/template_renderer_spec.rb spec/jobs/send_scheduled_message_job_spec.rb
git commit -m "TemplateRenderer resolve menções @{{nome}}/@{{numero}} e SendScheduledMessageJob as envia"
```

---

### Task 5: `SyncGroupsJob` sincroniza `group_participants`

**Files:**
- Modify: `rails-app/app/jobs/sync_groups_job.rb`
- Test: `rails-app/spec/jobs/sync_groups_job_spec.rb`

**Interfaces:**
- Consumes: `GroupParticipant` (Task 1). Payload esperado de `WaClient.groups` (stubado nos specs): `[{ "jid", "name", "participants_count", "participants" => [{ "jid", "name" }] }]` — chave `"participants"` é opcional (retrocompatibilidade com uma versão antiga do wa-service que ainda não a envia).
- Produces: nenhuma interface nova consumida por outra task; `GroupParticipant` fica populado após a sync.

- [ ] **Step 1: Adicionar os novos specs (falhando)**

```ruby
# rails-app/spec/jobs/sync_groups_job_spec.rb
require "rails_helper"

RSpec.describe SyncGroupsJob do
  let(:wa_service_url) { ENV.fetch("WA_SERVICE_URL") }

  it "faz upsert dos grupos retornados pelo wa-service" do
    stub_request(:get, "#{wa_service_url}/groups").to_return(
      status: 200,
      body: [ { jid: "g1@g.us", name: "Grupo 1", participants_count: 3 } ].to_json,
      headers: { "Content-Type" => "application/json" }
    )

    described_class.new.perform

    group = WhatsappGroup.find_by(jid: "g1@g.us")
    expect(group.name).to eq("Grupo 1")
    expect(group.participants_count).to eq(3)
    expect(group.synced_at).to be_present
  end

  it "sincroniza os participantes retornados junto com o grupo" do
    stub_request(:get, "#{wa_service_url}/groups").to_return(
      status: 200,
      body: [
        {
          jid: "g1@g.us",
          name: "Grupo 1",
          participants_count: 2,
          participants: [
            { jid: "5511999999999@s.whatsapp.net", name: "Caio" },
            { jid: "5511888888888@s.whatsapp.net", name: nil }
          ]
        }
      ].to_json,
      headers: { "Content-Type" => "application/json" }
    )

    described_class.new.perform

    group = WhatsappGroup.find_by(jid: "g1@g.us")
    expect(group.group_participants.count).to eq(2)

    caio = group.group_participants.find_by(jid: "5511999999999@s.whatsapp.net")
    expect(caio.name).to eq("Caio")
    expect(caio.phone_number).to eq("5511999999999")
  end

  it "remove participantes que saíram do grupo numa nova sincronização" do
    stub_request(:get, "#{wa_service_url}/groups").to_return(
      status: 200,
      body: [ { jid: "g1@g.us", name: "Grupo 1", participants_count: 2, participants: [
        { jid: "a@s.whatsapp.net", name: "A" }, { jid: "b@s.whatsapp.net", name: "B" }
      ] } ].to_json,
      headers: { "Content-Type" => "application/json" }
    ).then.to_return(
      status: 200,
      body: [ { jid: "g1@g.us", name: "Grupo 1", participants_count: 1, participants: [
        { jid: "a@s.whatsapp.net", name: "A" }
      ] } ].to_json,
      headers: { "Content-Type" => "application/json" }
    )

    described_class.new.perform
    described_class.new.perform

    group = WhatsappGroup.find_by(jid: "g1@g.us")
    expect(group.group_participants.pluck(:jid)).to eq([ "a@s.whatsapp.net" ])
  end

  it "mantém participantes já sincronizados quando o wa-service não envia a chave participants" do
    group = WhatsappGroup.create!(jid: "g1@g.us", name: "Grupo 1")
    GroupParticipant.create!(whatsapp_group: group, jid: "a@s.whatsapp.net", name: "A", phone_number: "a")

    stub_request(:get, "#{wa_service_url}/groups").to_return(
      status: 200,
      body: [ { jid: "g1@g.us", name: "Grupo 1", participants_count: 1 } ].to_json,
      headers: { "Content-Type" => "application/json" }
    )

    described_class.new.perform

    expect(group.reload.group_participants.count).to eq(1)
  end
end
```

- [ ] **Step 2: Rodar o spec e confirmar que os 3 novos exemplos falham**

Run: `cd rails-app && bundle exec rspec spec/jobs/sync_groups_job_spec.rb`
Expected: FAIL nos 3 novos exemplos (participantes nunca são criados); o primeiro exemplo (pré-existente) continua passando.

- [ ] **Step 3: Implementar**

```ruby
# rails-app/app/jobs/sync_groups_job.rb
class SyncGroupsJob
  include Sidekiq::Job

  def perform
    WaClient.groups.each { |group| sync_group(group) }
  end

  private

  def sync_group(group)
    wa_group = WhatsappGroup.find_or_initialize_by(jid: group["jid"])
    wa_group.update!(
      name: group["name"],
      participants_count: group["participants_count"],
      synced_at: Time.current
    )

    sync_participants(wa_group, group["participants"]) if group.key?("participants")
  end

  def sync_participants(wa_group, participants)
    rows = participants.map do |participant|
      {
        whatsapp_group_id: wa_group.id,
        jid: participant["jid"],
        phone_number: phone_number_from_jid(participant["jid"]),
        name: participant["name"],
        synced_at: Time.current
      }
    end

    GroupParticipant.upsert_all(rows, unique_by: [ :whatsapp_group_id, :jid ]) if rows.any?
    wa_group.group_participants.where.not(jid: rows.map { |row| row[:jid] }).delete_all
  end

  def phone_number_from_jid(jid)
    jid.to_s.split("@").first&.split(":")&.first
  end
end
```

- [ ] **Step 4: Rodar o spec e confirmar que passa**

Run: `cd rails-app && bundle exec rspec spec/jobs/sync_groups_job_spec.rb`
Expected: PASS (4 exemplos)

- [ ] **Step 5: Commit**

```bash
cd rails-app
git add app/jobs/sync_groups_job.rb spec/jobs/sync_groups_job_spec.rb
git commit -m "SyncGroupsJob sincroniza group_participants (upsert + remoção de quem saiu)"
```

---

### Task 6: wa-service — cache de nomes de contato (`contacts.upsert`/`contacts.update`)

**Contexto:** sem test runner no wa-service (decisão da spec) — verificação é via typecheck (`npm run build`) e checagem manual, não RSpec-style red/green.

**Files:**
- Modify: `wa-service/src/whatsapp.ts`

**Interfaces:**
- Produces: `getContactName(jid: string): string | undefined`, exportada de `whatsapp.ts`, usada pela Task 7.

- [ ] **Step 1: Adicionar o cache e os listeners de eventos**

```typescript
// wa-service/src/whatsapp.ts
import { rm } from "node:fs/promises";
import makeWASocket, {
  DisconnectReason,
  useMultiFileAuthState,
  type WASocket,
  type Contact,
} from "@whiskeysockets/baileys";
import { Boom } from "@hapi/boom";
import pino from "pino";
import qrcodeTerminal from "qrcode-terminal";

export type ConnectionStatus = "disconnected" | "qr_pending" | "connected";

const logger = pino({ level: "info" });

let sock: WASocket | undefined;
let status: ConnectionStatus = "disconnected";
let lastQR: string | undefined;

const contactNames = new Map<string, string>();

function cacheContacts(contacts: Partial<Contact>[]): void {
  for (const contact of contacts) {
    const name = contact.name ?? contact.notify;
    if (contact.id && name) {
      contactNames.set(contact.id, name);
    }
  }
}

async function connect(): Promise<void> {
  const { state, saveCreds } = await useMultiFileAuthState("./auth");

  sock = makeWASocket({
    auth: state,
    logger: logger.child({ module: "baileys" }),
  });

  sock.ev.on("creds.update", saveCreds);
  sock.ev.on("contacts.upsert", cacheContacts);
  sock.ev.on("contacts.update", cacheContacts);

  sock.ev.on("connection.update", (update) => {
    const { connection, lastDisconnect, qr } = update;

    if (qr) {
      lastQR = qr;
      status = "qr_pending";
      qrcodeTerminal.generate(qr, { small: true });
    }

    if (connection === "open") {
      status = "connected";
      lastQR = undefined;
      logger.info("Conectado ao WhatsApp");
    }

    if (connection === "close") {
      const statusCode = (lastDisconnect?.error as Boom | undefined)?.output
        ?.statusCode;
      const loggedOut = statusCode === DisconnectReason.loggedOut;

      status = "disconnected";

      if (loggedOut) {
        logger.warn("Sessão encerrada (logout). É necessário novo QR Code.");
      } else {
        logger.warn({ statusCode }, "Conexão perdida, reconectando...");
        connect();
      }
    }
  });
}

export function init(): void {
  connect();
}

export function getSocket(): WASocket | undefined {
  return sock;
}

export function getStatus(): ConnectionStatus {
  return status;
}

export function getLastQR(): string | undefined {
  return lastQR;
}

export function getContactName(jid: string): string | undefined {
  return contactNames.get(jid);
}

export async function logout(): Promise<void> {
  try {
    await sock?.logout();
  } catch (err) {
    logger.warn({ err }, "Erro ao encerrar sessão no WhatsApp, limpando estado local mesmo assim");
  }

  status = "disconnected";
  lastQR = undefined;
  sock = undefined;

  await rm("./auth", { recursive: true, force: true });

  await connect();
}
```

- [ ] **Step 2: Verificar que compila**

Run: `cd wa-service && npm run build`
Expected: sem erros de TypeScript.

- [ ] **Step 3: Commit**

```bash
cd wa-service
git add src/whatsapp.ts
git commit -m "wa-service: cacheia nomes de contato via eventos contacts.upsert/update"
```

---

### Task 7: wa-service — `GET /groups` inclui participantes com nome

**Files:**
- Modify: `wa-service/src/server.ts:49-65`

**Interfaces:**
- Consumes: `whatsapp.getContactName(jid)` (Task 6).
- Produces: `GET /groups` retorna, por grupo, `participants: [{ jid: string, name: string | undefined }]` além dos campos já existentes (`jid`, `name`, `participants_count`) — é esse payload que `SyncGroupsJob` (Task 5) espera.

- [ ] **Step 1: Implementar**

```typescript
// wa-service/src/server.ts — substituir o handler de GET /groups
app.get("/groups", async (_req, res) => {
  const sock = whatsapp.getSocket();

  if (whatsapp.getStatus() !== "connected" || !sock) {
    res.status(503).json({ error: "not_connected" });
    return;
  }

  const groups = await sock.groupFetchAllParticipating();
  const list = Object.values(groups).map((group) => ({
    jid: group.id,
    name: group.subject,
    participants_count: group.participants.length,
    participants: group.participants.map((participant) => ({
      jid: participant.id,
      name: whatsapp.getContactName(participant.id),
    })),
  }));

  res.json(list);
});
```

- [ ] **Step 2: Verificar que compila**

Run: `cd wa-service && npm run build`
Expected: sem erros de TypeScript.

- [ ] **Step 3: Commit**

```bash
cd wa-service
git add src/server.ts
git commit -m "wa-service: GET /groups inclui participantes (jid + nome)"
```

---

### Task 8: wa-service — `POST /send` aceita `mentions`

**Files:**
- Modify: `wa-service/src/server.ts:19-29,67-84`

**Interfaces:**
- Consumes: `mentions?: string[]` vindo no body de `POST /send` (enviado por `WaClient.send_message`, Task 3).
- Produces: `sock.sendMessage(jid, { text, mentions })` quando `mentions` não está vazio (Baileys popula `contextInfo.mentionedJid`).

- [ ] **Step 1: Atualizar `sendLikeAHuman` para aceitar `mentions`**

```typescript
// wa-service/src/server.ts
async function sendLikeAHuman(sock: WASocket, jid: string, message: string, mentions?: string[]): Promise<void> {
  await sock.sendPresenceUpdate("composing", jid);
  await sleep(2_000);
  await sock.sendPresenceUpdate("paused", jid);

  await sleep(randomSeconds(3, 12) * 1_000);

  const content = mentions && mentions.length > 0 ? { text: message, mentions } : { text: message };
  await sock.sendMessage(jid, content);
}
```

(a assinatura `{ text: message, mentions }` só é usada quando `mentions` é de fato um `string[]` não vazio — necessário porque `tsconfig.json` tem `exactOptionalPropertyTypes: true`, que rejeita atribuir `mentions: undefined` explicitamente a uma propriedade opcional tipada como `string[]`)

- [ ] **Step 2: Validar e repassar `mentions` no handler de `POST /send`**

```typescript
// wa-service/src/server.ts
app.post("/send", async (req, res) => {
  const sock = whatsapp.getSocket();

  if (whatsapp.getStatus() !== "connected" || !sock) {
    res.status(503).json({ error: "not_connected" });
    return;
  }

  const { group_jid, message, mentions } = req.body ?? {};

  if (typeof group_jid !== "string" || typeof message !== "string") {
    res.status(400).json({ error: "invalid_params" });
    return;
  }

  if (mentions !== undefined && (!Array.isArray(mentions) || !mentions.every((m) => typeof m === "string"))) {
    res.status(400).json({ error: "invalid_params" });
    return;
  }

  await sendLikeAHuman(sock, group_jid, message, mentions);
  res.json({ status: "sent" });
});
```

- [ ] **Step 3: Verificar que compila**

Run: `cd wa-service && npm run build`
Expected: sem erros de TypeScript.

- [ ] **Step 4: Commit**

```bash
cd wa-service
git add src/server.ts
git commit -m "wa-service: POST /send aceita mentions e repassa pro Baileys"
```

---

### Task 9: Admin UI — página de participantes do grupo

**Files:**
- Modify: `rails-app/config/routes.rb:14`
- Modify: `rails-app/app/controllers/groups_controller.rb`
- Modify: `rails-app/app/views/groups/index.html.erb`
- Create: `rails-app/app/views/groups/show.html.erb`

**Interfaces:**
- Consumes: `WhatsappGroup#group_participants` (Task 1), dados populados por `SyncGroupsJob` (Task 5).
- Produces: rota `GET /groups/:id` (`group_path(group)`).

**Nota:** este projeto não tem specs de controller/view (`GroupsController` não tem nenhum hoje) — esta tarefa segue o padrão existente e não introduz esse tipo de teste; a verificação é manual.

- [ ] **Step 1: Habilitar a rota `show`**

```ruby
# rails-app/config/routes.rb
resources :groups, only: [ :index, :show ] do
  collection do
    post :sync
  end
end
```

- [ ] **Step 2: Adicionar a action `show`**

```ruby
# rails-app/app/controllers/groups_controller.rb
class GroupsController < ApplicationController
  def index
    @groups = WhatsappGroup.order(:name)
  end

  def show
    @group = WhatsappGroup.find(params[:id])
    @participants = @group.group_participants.order(:name)
  end

  def sync
    SyncGroupsJob.new.perform
    redirect_to groups_path, notice: "Grupos sincronizados."
  rescue WaClient::NotConnected
    redirect_to groups_path, alert: "WhatsApp não está conectado."
  rescue WaClient::Error, Faraday::ConnectionFailed, Faraday::TimeoutError => e
    redirect_to groups_path, alert: "Erro ao sincronizar: #{e.message}"
  end
end
```

- [ ] **Step 3: Criar a view `show.html.erb`**

```erb
<%# rails-app/app/views/groups/show.html.erb %>
<% content_for :title, @group.name %>

<div class="flex items-center justify-between mb-6">
  <h1 class="text-2xl font-bold"><%= @group.name %></h1>
  <%= link_to "Voltar", groups_path, class: "text-sm text-gray-600 hover:underline" %>
</div>

<p class="text-xs text-gray-500 mb-4">
  Use estes nomes ou números com <code class="font-mono">@{{nome}}</code> ou
  <code class="font-mono">@{{numero}}</code> no corpo de um template para mencionar
  o participante ao enviar para este grupo.
</p>

<table class="w-full text-sm border-collapse bg-white shadow rounded overflow-hidden">
  <thead class="bg-gray-100">
    <tr class="text-left">
      <th class="py-2 px-3">Nome</th>
      <th class="py-2 px-3">Número</th>
    </tr>
  </thead>
  <tbody>
    <% @participants.each do |participant| %>
      <tr class="border-t">
        <td class="py-2 px-3"><%= participant.name.presence || "—" %></td>
        <td class="py-2 px-3 font-mono text-xs"><%= participant.phone_number %></td>
      </tr>
    <% end %>
    <% if @participants.empty? %>
      <tr><td colspan="2" class="py-4 px-3 text-center text-gray-500">Nenhum participante sincronizado ainda.</td></tr>
    <% end %>
  </tbody>
</table>
```

- [ ] **Step 4: Linkar o nome do grupo na listagem**

```erb
<%# rails-app/app/views/groups/index.html.erb — trocar só a célula do nome %>
<td class="py-2 px-3"><%= link_to group.name, group_path(group), class: "text-blue-700 hover:underline" %></td>
```

- [ ] **Step 5: Verificação manual**

Run: `cd rails-app && bin/rails routes | grep groups`
Expected: aparece `GET /groups/:id groups#show`.

Rodar `bin/dev`, ir em Grupos, sincronizar (precisa do wa-service conectado — se não estiver, criar um `WhatsappGroup`/`GroupParticipant` via `bin/rails console` para checar a tela), clicar no nome de um grupo e confirmar que a lista de participantes aparece.

- [ ] **Step 6: Rodar a suíte inteira do Rails para garantir que nada quebrou**

Run: `cd rails-app && bundle exec rspec`
Expected: PASS (toda a suíte, incluindo as tasks anteriores)

- [ ] **Step 7: Commit**

```bash
cd rails-app
git add config/routes.rb app/controllers/groups_controller.rb \
  app/views/groups/index.html.erb app/views/groups/show.html.erb
git commit -m "Admin: página de detalhe do grupo lista participantes sincronizados"
```
