# Plano de Execução — WhatsApp Group Scheduler

> Cole este arquivo na raiz do projeto e peça ao Claude Code para executar fase por fase.
> Sugestão de prompt inicial: *"Leia PLANO_WHATSAPP_SCHEDULER.md e execute a Fase 0. Pare ao final e me mostre o resultado."*

---

## Contexto

Aplicação self-hosted para definir templates de mensagem, agendar envios e disparar mensagens em grupos de WhatsApp. Alternativa simplificada ao PlugSend.

**Stack:**
- **Rails 7.1+ (API + views ERB/Hotwire)** — templates, agendamentos, admin, logs
- **Node.js + Baileys** — microserviço que mantém a sessão WhatsApp e envia mensagens
- **PostgreSQL** — persistência
- **Sidekiq + sidekiq-cron** — agendamento e retries
- **Docker Compose** — orquestração local

**Por que dois serviços:** Baileys é Node-only e precisa de um processo long-running com a sessão WebSocket ativa. O Rails não deve segurar esse estado.

### ⚠️ Aviso importante
Baileys é uma biblioteca **não-oficial** que viola os Termos de Serviço do WhatsApp. Riscos reais:
- Bloqueio temporário ou permanente do número
- Perda de acesso a grupos

**Regras obrigatórias do projeto:**
1. Usar sempre um número secundário/descartável
2. Implementar rate limiting agressivo (ver Fase 5)
3. Nunca fazer envio em massa ou mensagens idênticas repetidas em curto intervalo

---

## Fase 0 — Setup do repositório

**Objetivo:** estrutura de pastas e Docker Compose funcionando.

```
whatsapp-scheduler/
├── docker-compose.yml
├── .env.example
├── rails-app/
└── wa-service/
```

Tarefas:
1. Criar `rails-app` com `rails new rails-app --database=postgresql --css=tailwind`
2. Criar `wa-service` com `npm init` + TypeScript
3. `docker-compose.yml` com serviços: `db` (postgres:16), `redis` (redis:7), `rails`, `wa`
4. `.env.example` com:
   ```
   DATABASE_URL=
   REDIS_URL=
   WA_SERVICE_URL=http://wa:3001
   INTERNAL_API_TOKEN=          # gerar com SecureRandom.hex(32)
   RAILS_MASTER_KEY=
   ```
5. Volume nomeado `wa_auth` montado em `/app/auth` no serviço `wa` (persistir sessão entre restarts)

**Critério de aceite:** `docker compose up` sobe os 4 containers sem erro.

---

## Fase 1 — Microserviço WhatsApp (`wa-service`)

**Objetivo:** conectar ao WhatsApp via QR Code e expor API interna de envio.

### Dependências
```
@whiskeysockets/baileys, express, pino, qrcode-terminal, dotenv, typescript, tsx
```

### Arquivos

**`src/whatsapp.ts`** — singleton da conexão:
- `useMultiFileAuthState('./auth')` para persistir credenciais
- Reconexão automática no evento `connection.update` quando `lastDisconnect.error` **não** for `DisconnectReason.loggedOut`
- Exportar: `getSocket()`, `getStatus()`, `getLastQR()`
- Estado interno: `disconnected | qr_pending | connected`

**`src/server.ts`** — Express na porta 3001:

| Método | Rota | Descrição |
|---|---|---|
| GET | `/health` | `{ status, connected: bool }` |
| GET | `/qr` | Retorna QR atual como data URL (para exibir no Rails) |
| GET | `/groups` | Lista grupos via `sock.groupFetchAllParticipating()` → `[{ jid, name, participants_count }]` |
| POST | `/send` | Body `{ group_jid, message }` → envia texto |
| POST | `/logout` | Encerra sessão e limpa `./auth` |

**`src/middleware/auth.ts`** — compara header `Authorization` com `process.env.INTERNAL_API_TOKEN` usando comparação de tempo constante (`crypto.timingSafeEqual`).

### Regras
- Todas as rotas exceto `/health` exigem o token
- Se `/send` for chamado com socket desconectado → HTTP 503 com `{ error: "not_connected" }`
- O serviço **nunca** é exposto publicamente; só acessível na rede interna do Docker

**Critério de aceite:** `docker compose logs wa` mostra o QR; após escanear, `GET /groups` retorna a lista de grupos.

---

## Fase 2 — Modelos e migrations (Rails)

```ruby
# templates
t.string  :name, null: false
t.text    :body, null: false          # suporta {{variavel}}
t.jsonb   :default_variables, default: {}
t.boolean :active, default: true
t.timestamps
# index unique em name

# whatsapp_groups  (cache local da lista vinda do wa-service)
t.string   :jid, null: false          # ex: 120363...@g.us
t.string   :name
t.integer  :participants_count
t.datetime :synced_at
t.timestamps
# index unique em jid

# schedules
t.references :template, null: false, foreign_key: true
t.references :whatsapp_group, null: false, foreign_key: true
t.jsonb    :variables, default: {}
t.string   :cron_expression           # ex: "0 9 * * 1-5" (nil se one-off)
t.datetime :run_at                    # preenchido se one-off
t.datetime :next_run_at               # calculado
t.string   :timezone, default: "America/Sao_Paulo"
t.boolean  :active, default: true
t.datetime :last_run_at
t.timestamps
# index em [:active, :next_run_at]

# message_logs
t.references :schedule, foreign_key: true   # nullable (envio manual)
t.string  :group_jid
t.text    :rendered_body
t.string  :status, default: "pending"       # pending/sent/failed
t.text    :error_message
t.datetime :sent_at
t.timestamps
```

### Validações
- `Template#body` — extrair variáveis com `body.scan(/\{\{(\w+)\}\}/)`, expor como `Template#variable_names`
- `Schedule` — validar que ou `cron_expression` ou `run_at` está presente (XOR)
- `Schedule` — validar `cron_expression` com a gem `fugit` (`Fugit.parse_cron`)
- `Schedule` — validar que todas as `variable_names` do template têm valor em `variables` ou `default_variables`

---

## Fase 3 — Camada de serviço

**`app/services/wa_client.rb`** — wrapper HTTP do microserviço:
```ruby
class WaClient
  Error = Class.new(StandardError)
  NotConnected = Class.new(Error)

  def self.send_message(group_jid:, message:)
  def self.groups
  def self.status
  def self.qr_code
end
```
- Usar `Faraday` com timeout de 15s
- Levantar `NotConnected` no 503
- Ler `ENV["WA_SERVICE_URL"]` e `ENV["INTERNAL_API_TOKEN"]`

**`app/services/template_renderer.rb`**
```ruby
TemplateRenderer.call(template, variables) # => String
```
- Substitui `{{chave}}` pelos valores
- Levanta erro se sobrar variável não preenchida
- Escapa nada (é texto puro, não HTML)

**`app/services/schedule_calculator.rb`**
```ruby
ScheduleCalculator.next_run(schedule) # => Time ou nil
```
- One-off: retorna `run_at` se ainda não executou, senão `nil`
- Recorrente: `Fugit.parse_cron(expr).next_time(from).to_t` respeitando `schedule.timezone`

---

## Fase 4 — Jobs (Sidekiq)

**`DispatchDueSchedulesJob`** — roda a cada minuto via sidekiq-cron:
```ruby
Schedule.where(active: true)
        .where("next_run_at <= ?", Time.current)
        .find_each { |s| SendScheduledMessageJob.perform_async(s.id) }
```
Marcar `next_run_at` como `nil` antes de enfileirar (evita duplicata se o job demorar).

**`SendScheduledMessageJob`**:
1. Carregar schedule
2. Renderizar template
3. Criar `MessageLog` com status `pending`
4. Chamar `WaClient.send_message`
5. Atualizar log para `sent` + `sent_at`, ou `failed` + `error_message`
6. Atualizar `schedule.last_run_at` e recalcular `next_run_at`
7. Se recorrente e `next_run_at` for nil → desativar schedule

Config do Sidekiq: `retry: 3`, `backoff` exponencial. Em caso de `NotConnected`, **não** fazer retry automático (o problema é sessão, não transiente) — logar como failed.

**`SyncGroupsJob`** — a cada 30min, chama `WaClient.groups` e faz upsert em `whatsapp_groups`.

---

## Fase 5 — Rate limiting e proteções

Implementar **antes** de qualquer envio real:

1. **Throttle global** — máximo 1 envio a cada 20 segundos por número. Usar `Sidekiq::Limiter.window` ou lock em Redis (`SETNX` com TTL).
2. **Delay aleatório** — antes de cada `sendMessage`, dormir `rand(3..12)` segundos no wa-service.
3. **Presence simulation** — no Baileys, chamar `sock.sendPresenceUpdate('composing', jid)`, aguardar ~2s, depois `'paused'`, então enviar.
4. **Cap diário** — constante `MAX_DAILY_SENDS = 50`; se `MessageLog.where(status: "sent", sent_at: Date.current.all_day).count >= cap`, abortar e logar.
5. **Guard de duplicidade** — bloquear envio se mensagem idêntica foi enviada ao mesmo grupo nas últimas 6h.

---

## Fase 6 — Interface admin

Views Rails com Tailwind + Turbo. Telas mínimas:

1. **`/connection`** — status da sessão, QR Code (auto-refresh a cada 5s via Turbo Stream enquanto `qr_pending`), botão de logout
2. **`/templates`** — CRUD; preview mostrando variáveis detectadas
3. **`/groups`** — lista sincronizada, botão "Sincronizar agora"
4. **`/schedules`** — CRUD; campo de cron com preview em texto (`Fugit::Cron#rough_frequency`) e próximas 3 execuções
5. **`/logs`** — tabela paginada com filtro por status; botão "Reenviar" para os `failed`
6. **Botão "Enviar teste agora"** em cada schedule

Autenticação: HTTP Basic simples via `http_basic_authenticate_with` (é single-user, self-hosted).

---

## Fase 7 — Testes

- **RSpec** para services (`TemplateRenderer`, `ScheduleCalculator`) e jobs
- **WebMock** para stubar o wa-service
- Casos críticos:
  - Cron com timezone São Paulo atravessando horário de verão
  - Schedule one-off não reagenda
  - `NotConnected` não dispara retry
  - Rate limit bloqueia o segundo envio dentro da janela
  - Variável faltando levanta erro antes de criar o log

---

## Ordem de execução recomendada

| Fase | Entregável verificável |
|---|---|
| 0 | `docker compose up` sobe tudo |
| 1 | QR escaneado, `/groups` responde |
| 2 | `rails db:migrate` + seeds criam template de exemplo |
| 3 | Console: `WaClient.status` retorna connected |
| 5 | Rate limiter testado isoladamente |
| 4 | Envio agendado chega no grupo de teste |
| 6 | Admin navegável |
| 7 | Suite verde |

> **Nota:** a Fase 5 vem antes da 4 de propósito. Não dispare o primeiro envio real sem proteção.

---

## Prompts sugeridos para o Claude Code

```
Fase 0: "Execute a Fase 0 do PLANO_WHATSAPP_SCHEDULER.md. Não crie código de
aplicação ainda, só a estrutura e o Docker Compose."

Fase 1: "Execute a Fase 1. Use TypeScript estrito. Ao final, me mostre como
rodar só o wa-service para escanear o QR."

Fase 2+3: "Execute as Fases 2 e 3. Escreva as migrations, models com validações
e os três services. Rode rubocop ao final."

Fase 5: "Execute a Fase 5. Escreva testes RSpec para cada proteção antes de
integrar aos jobs."
```
