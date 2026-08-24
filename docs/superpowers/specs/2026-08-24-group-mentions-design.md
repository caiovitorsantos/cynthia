# Menção de participantes em mensagens de grupo

Data: 2026-08-24

## Contexto e objetivo

Hoje o envio de mensagens para grupos do WhatsApp (`WaClient.send_message` →
`wa-service` → Baileys `sock.sendMessage`) não suporta marcar (`@mencionar`)
participantes do grupo. O objetivo é permitir que o autor de um `Template`
insira placeholders no corpo da mensagem que, ao serem renderizados para um
`Schedule` específico, virem menções reais (destacadas e notificando o
participante) no WhatsApp.

A biblioteca usada por baixo (Baileys) já suporta menções nativamente via
`sock.sendMessage(jid, { text, mentions: string[] })`, que popula
`contextInfo.mentionedJid` na mensagem do protocolo. O trabalho é conectar
essa capacidade ao pipeline existente.

## Decisões de escopo

- Sintaxe no template: **`@{{nome}}`** (casa por nome/apelido sincronizado do
  participante) **ou `@{{numero}}`** (casa por número de telefone).
- Participantes não são selecionados manualmente numa tela — o autor do
  template digita o placeholder diretamente no corpo da mensagem.
- Se o nome ou número não for encontrado, **ou** o nome for ambíguo (dois
  participantes com o mesmo nome), a mensagem é enviada mesmo assim, só que
  **sem** aquele participante sendo mencionado (degrada, não falha o envio).
  Um aviso é logado para permitir revisão posterior.
- O cache de nomes de contato coletado pelo Baileys é persistido no banco
  Rails via sincronização (mesmo padrão já usado para grupos), não só em
  memória no `wa-service`.
- Uma página de detalhe do grupo é adicionada no admin, listando os
  participantes sincronizados (nome + número), para o autor do template saber
  o que digitar.

## Por que nomes não estão disponíveis hoje

`sock.groupFetchAllParticipating()` (usado em `GET /groups`) retorna, por
participante, apenas `id` (JID) e `admin` — não há nome. Nomes de contato
(`name`/`notify`) só chegam via eventos separados do Baileys
(`contacts.upsert`/`contacts.update`), disparados com a lista de contatos
salvos no celular conectado e conforme mensagens/interações acontecem. O
`wa-service` hoje não escuta nem armazena esses eventos — isso precisa ser
adicionado.

**Limitação conhecida:** grupos com `addressingMode: "lid"` (endereçamento
anônimo) têm JIDs de participante que não são números de telefone reais —
`@{{numero}}` não é útil nesses grupos. Caso raro, documentado aqui e não
tratado especialmente.

## Arquitetura / fluxo

```
Baileys eventos (contacts.upsert/update)
        │
        ▼
wa-service: cache jid -> name (em memória)
        │
        ▼
GET /groups  ──────────────►  SyncGroupsJob (Rails)
  { jid, name, participants_count,        │
    participants: [{ jid, name }] }       ▼
                                  whatsapp_groups + group_participants (upsert)

Template.body com @{{nome}} / @{{numero}}
        │
        ▼
TemplateRenderer.call(template, variables, whatsapp_group:)
  resolve tokens de menção contra group_participants do grupo
  → body renderizado (com "@numero" no lugar do token) + mentioned_jids[]
        │
        ▼
WaClient.send_message(group_jid:, message:, mentions: mentioned_jids)
        │
        ▼
POST /send { group_jid, message, mentions }  ──►  wa-service
        │
        ▼
sock.sendMessage(jid, { text: message, mentions })
```

## Componentes

### 1. Dados (Rails)

Nova tabela `group_participants`:

```ruby
create_table :group_participants do |t|
  t.references :whatsapp_group, null: false, foreign_key: true
  t.string :jid, null: false
  t.string :phone_number
  t.string :name
  t.datetime :synced_at
  t.timestamps
end
add_index :group_participants, [:whatsapp_group_id, :jid], unique: true
```

`phone_number` é derivado do `jid` na sincronização (`jid.split('@').first.split(':').first`),
armazenado para permitir casar `@{{numero}}` sem reprocessar o JID a cada
renderização.

Model:

```ruby
class GroupParticipant < ApplicationRecord
  belongs_to :whatsapp_group
  validates :jid, presence: true, uniqueness: { scope: :whatsapp_group_id }
end
```

`WhatsappGroup` ganha `has_many :group_participants, dependent: :destroy`.

### 2. wa-service

`whatsapp.ts`:
- Mantém `const contactNames = new Map<string, string>()`.
- `sock.ev.on("contacts.upsert", contacts => { for (c of contacts) if (c.id && (c.name || c.notify)) contactNames.set(c.id, c.name ?? c.notify) })`.
- `sock.ev.on("contacts.update", ...)` análogo, para atualizações parciais.
- Exporta `getContactName(jid: string): string | undefined`.

`server.ts`:
- `GET /groups`: para cada grupo, além de `jid`/`name`/`participants_count`
  já existentes, inclui `participants: group.participants.map(p => ({ jid: p.id, name: getContactName(p.id) }))`.
- `POST /send`: aceita `mentions?: string[]` opcional no body (validar que,
  se presente, é array de strings); repassa para `sendLikeAHuman`, que passa
  `mentions` para `sock.sendMessage(jid, { text: message, mentions })`
  (omitido/`undefined` quando vazio, para não alterar comportamento atual de
  mensagens sem menção).

### 3. Rails — sincronização

`SyncGroupsJob`:
- Mantém o upsert de `WhatsappGroup` (ajustado para obter o `id` do registro
  upsertado, necessário para os participantes).
- Para cada grupo, `upsert_all` dos participantes retornados por `GET /groups`
  (`jid`, `phone_number` derivado, `name`, `synced_at`), únicos por
  `[whatsapp_group_id, jid]`.
- Remove (`delete_all`) participantes da tabela que não vieram mais na
  resposta (saíram do grupo).

### 4. Rails — renderização e envio

`TemplateRenderer`:
- Nova regex própria para tokens de menção, distinta da de variáveis comuns:
  `MENTION_PATTERN = /@\{\{([^{}]+)\}\}/`.
- `self.call(template, variables, whatsapp_group: nil)` passa a:
  (`whatsapp_group` é keyword opcional — hoje só `SendScheduledMessageJob`
  chama `TemplateRenderer.call`; se `nil`, tokens de menção sempre degradam
  por falta de contexto, sem levantar erro)
  1. Rodar primeiro a substituição de tokens de menção: para cada match,
     normaliza a chave (`strip`); se for só dígitos (após remover
     formatação), resolve por `phone_number` contra
     `whatsapp_group.group_participants`; senão resolve por `name`
     (case-insensitive). Resolvido com exatamente 1 resultado → substitui o
     token por `"@#{participant.phone_number}"` e coleta o `jid` numa lista
     de mentions. Zero ou múltiplos resultados → mantém o texto original do
     token sem o wrapper (`@nome`), loga aviso via `Rails.logger.warn`, não
     adiciona à lista de mentions.
  2. Rodar a substituição de variáveis comuns (`VARIABLE_PATTERN`) como já
     existe hoje, inalterada.
  3. Retornar um `Struct`/objeto simples com `body` e `mentioned_jids`
     (ex.: `TemplateRenderer::Result = Struct.new(:body, :mentioned_jids)`),
     em vez de só a string — mudança de interface do método.

`SendScheduledMessageJob`:
- Passa `whatsapp_group: schedule.whatsapp_group` para `TemplateRenderer.call`.
- Usa `result.body` no lugar de `rendered_body` e passa
  `mentions: result.mentioned_jids` para `WaClient.send_message`.

`WaClient`:
- `send_message(group_jid:, message:, mentions: [])` inclui `mentions` no
  payload JSON enviado para `/send`.

### 5. UI (admin)

`GroupsController#show` (nova action) + `app/views/groups/show.html.erb`:
lista os `group_participants` do grupo (nome, número), somente leitura.
Link a partir de `groups/index.html.erb`.

## Tratamento de erros

- Nome/número não encontrado ou ambíguo: mensagem enviada sem aquele
  participante marcado; aviso logado (`Rails.logger.warn`), sem impacto no
  `MessageLog` (status continua `sent` normalmente — não é uma falha de
  envio).
- `wa-service` fora do ar durante `GET /groups`: comportamento inalterado
  (já tratado por `WaClient::NotConnected`/`WaClient::Error` no
  `GroupsController#sync` existente).
- `mentions` malformado no `POST /send` (não é array): `wa-service` responde
  `400 invalid_params`, mesmo padrão já usado para `group_jid`/`message`
  inválidos.

## Testes

Lado Rails (RSpec, já configurado no projeto):
- `GroupParticipant`: validações (presença de `jid`, unicidade por grupo).
- `TemplateRenderer`: resolução por nome (case-insensitive), resolução por
  número, nome ambíguo (degrada), nome/número inexistente (degrada), mistura
  de menção + variáveis comuns no mesmo template.
- `SyncGroupsJob`: upsert de participantes novos, atualização de existentes,
  remoção de quem saiu do grupo.
- `SendScheduledMessageJob`: `mentions` chegando corretamente até
  `WaClient.send_message`.

Lado wa-service: o projeto não tem test runner configurado hoje (`npm test`
é um stub). Não introduzir infraestrutura de teste nova como parte desta
feature — a mudança em `server.ts`/`whatsapp.ts` é verificada manualmente
(igual ao padrão atual do wa-service). Fica fora de escopo adicionar testes
automatizados ali.

## Fora de escopo

- Seleção manual de participantes na tela de agendamento.
- Menção automática de "todos" (`@{{todos}}`).
- Tratamento especial para grupos `addressingMode: "lid"`.
- Infraestrutura de testes automatizados para o `wa-service`.
