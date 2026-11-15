// Canal do WhatsApp pelo webhook (contrato do wa-service) com o wa falso e a Anthropic falsa:
// RF-10, RF-13, RF-19, RF-22, RF-25 a RF-29, TM-03/04/05/15/21.
import { test, expect } from "@playwright/test";
import { env, login, groupId, webhook, waReset, waLog, waState, anthropicQueue, piiIn } from "./support/helpers";
import { rails, clearThrottle, wa } from "./support/stack";

const G = "e2e-volei@g.us";
const jid = (n: number) => `55000000000${String(n).padStart(2, "0")}@s.whatsapp.net`;
const sentTo = async (request: any) => (await waLog(request)).sent.filter((s) => s.group_jid === G);
let msg = 0;
const mid = () => `e2e-in-${Date.now()}-${msg++}`;

// Ordem fixa (1 worker, arquivo em sequência), mas sem "serial": uma falha não pula os testes seguintes.
test.describe.configure({ mode: "default" });

test.beforeAll(async ({ request }) => {
  await waReset(request);
  await waState(request, "connected");
});

test("RF-22/TM-15: webhook sem token ou com token errado é 401 e nada roda", async ({ request }) => {
  const before = rails(`print MessageLog.count`);
  for (const token of ["", "e2e-token-errado"]) {
    const res = await webhook(request, { group_jid: G, kind: "command", message_id: mid(), participant_jid: jid(1), text: "!espera x" }, token);
    expect(res.status()).toBe(401);
  }
  await new Promise((r) => setTimeout(r, 2000));
  expect(rails(`print MessageLog.count`)).toBe(before);
  expect(await sentTo(request)).toEqual([]);
  // wa falso exige o mesmo token (RF-22 do lado do wa-service fica em auth.test.ts); /send desconectado é 503
});

test("RF-10/RF-19: !Espera (maiúsculas) de não admin roda com remetente, argumento e assinatura", async ({ request }) => {
  clearThrottle();
  const res = await webhook(request, { group_jid: G, kind: "command", message_id: mid(), participant_jid: jid(3), push_name: "e2e-Pessoa3", text: "!Espera e2e-Bruno" });
  expect(res.status()).toBe(204);
  await expect.poll(async () => (await sentTo(request)).map((s) => s.message).join("\n"), { timeout: 30_000 }).toContain("e2e-Pessoa3 entrou na espera: e2e-Bruno");
  const message = (await sentTo(request)).at(-1).message as string;
  const options = rails(`print WhatsappGroup.find_by(jid: "${G}").signature`).split("|").map((s) => s.trim());
  expect(options.some((o) => message.trimEnd().endsWith(o)), `termina com uma opção da assinatura: ${message}`).toBe(true);
  expect(rails(`print WhatsappGroup.find_by(jid: "${G}").member_lists.find_by(key: "avulsos").group_participants.exists?(jid: "${jid(3)}")`)).toBe("true");
});

test("RF-27/TM-21: comando que altera dados só para admin", async ({ request }) => {
  rails(`g = WhatsappGroup.find_by(jid: "${G}"); g.flows.where(command: "!setpix").delete_all; g.flows.create!(name: "e2e-setpix", trigger: "command", command: "!setpix", steps: [{ "type" => "set_variable", "name" => "pix", "value" => "{{argumento}}" }])`);
  clearThrottle();
  await webhook(request, { group_jid: G, kind: "command", message_id: mid(), participant_jid: jid(4), push_name: "e2e-Pessoa4", text: "!setpix e2e-atacante" });
  await expect.poll(async () => (await sentTo(request)).map((s) => s.message).join("\n"), { timeout: 30_000 }).toContain("!setpix é só pra admin");
  expect(rails(`print WhatsappGroup.find_by(jid: "${G}").variables["pix"]`)).toBe("e2e-pix@example.invalid");
  // admin (Pessoa1) roda
  await webhook(request, { group_jid: G, kind: "command", message_id: mid(), participant_jid: jid(1), push_name: "e2e-Pessoa1", text: "!setpix e2e-pix2@example.invalid" });
  await expect.poll(() => rails(`print WhatsappGroup.find_by(jid: "${G}").variables["pix"]`), { timeout: 20_000 }).toBe("e2e-pix2@example.invalid");
  rails(`g = WhatsappGroup.find_by(jid: "${G}"); g.update!(variables: g.variables.merge("pix" => "e2e-pix@example.invalid"))`);
});

test("RF-13: reação ✅/❌ registra presença na rodada e remover desfaz; painel mostra", async ({ page, request }) => {
  rails(`MessageLog.create!(group_jid: "${G}", status: "sent", sent_at: Time.current, opens_round: true, wa_message_id: "e2e-round-1", rendered_body: "e2e-rodada")`);
  await webhook(request, { group_jid: G, kind: "reaction", message_id: "e2e-round-1", participant_jid: jid(2), text: "✅" });
  await webhook(request, { group_jid: G, kind: "reaction", message_id: "e2e-round-1", participant_jid: jid(3), text: "❌" });
  await webhook(request, { group_jid: G, kind: "reaction", message_id: "e2e-round-1", participant_jid: jid(1), text: "✅" });
  await webhook(request, { group_jid: G, kind: "reaction", message_id: "e2e-round-1", participant_jid: jid(1), text: "" });
  const statuses = rails(`print Attendance::Response.where(message_log: MessageLog.find_by(wa_message_id: "e2e-round-1")).joins(:group_participant).pluck("group_participants.jid", :status).sort.inspect`);
  expect(statuses).toBe(`[["${jid(2)}", "confirmed"], ["${jid(3)}", "declined"]]`);
  await login(page);
  await page.goto(`/groups/${await groupId(page, "e2e-volei")}`);
  await expect(page.locator("#membros tr", { hasText: "e2e-Pessoa2" })).toContainText("✅");
  await expect(page.locator("#membros tr", { hasText: "e2e-Pessoa3" })).toContainText("❌");
});

test("RF-25/RF-28/RF-29: 1a menção envia o aviso antes de chamar a Anthropic; resposta marca quem perguntou com {{pix}} preenchido", async ({ page, request }) => {
  await waReset(request);
  clearThrottle();
  expect(rails(`print WhatsappGroup.find_by(jid: "${G}").ai_notice_sent_at.inspect`)).toBe("nil");
  await anthropicQueue(request, [{ tool_use: { name: "get_group", input: { group_id: 999999 } } }, { text: "O pix é {{pix}}" }]);
  await webhook(request, { group_jid: G, kind: "mention", message_id: mid(), participant_jid: jid(5), push_name: "e2e-Pessoa5", text: "@5500000000000 qual o pix? meu fone 5500000000005" });

  await expect.poll(async () => (await sentTo(request)).length, { timeout: 90_000 }).toBeGreaterThanOrEqual(2); // a resposta espera a janela de 20 s do aviso
  const log = await waLog(request);
  const [notice, reply] = log.sent.filter((s) => s.group_jid === G);
  expect(notice.message).toContain("Anthropic");
  expect(log.anthropic.length).toBeGreaterThan(0);
  expect(notice.at, "aviso enviado antes da 1a chamada à Anthropic").toBeLessThan(log.anthropic[0].at);
  expect(reply.message.startsWith("@5500000000005 ")).toBe(true);
  expect(reply.message).toContain("O pix é e2e-pix@example.invalid");
  expect(reply.mentions).toEqual([jid(5)]);
  expect.soft(piiIn(log.anthropic), "PII no payload da Anthropic (grupo)").toEqual([]);
  // TM-07: get_group com outro id devolve o grupo da menção; list_groups ausente; não admin sem propose_* (TM-05)
  expect(JSON.stringify(log.anthropic[1].messages)).toContain('\\"name\\":\\"e2e-volei\\"');
  const tools = log.anthropic[0].tools.map((t: any) => t.name);
  expect(tools).not.toContain("list_groups");
  expect(tools.filter((t: string) => t.startsWith("propose_"))).toEqual([]);
  expect(JSON.stringify(log.anthropic[0].system)).toContain("Brazilian Portuguese"); // idioma do grupo
  expect(rails(`print MessageLog.where(group_jid: "${G}", kind: "ai_notice").count`)).toBe("1");

  await login(page);
  await page.goto(`/groups/${await groupId(page, "e2e-volei")}`);
  await expect(page.getByText(/Aviso de IA: enviado em \d{2}\/\d{2}\/\d{4}/)).toBeVisible();
});

test("TM-04/RF-26: 2a menção (admin) não reenvia o aviso; proposta só executa com 'sim' de admin citando", async ({ request }) => {
  await waReset(request);
  clearThrottle();
  await anthropicQueue(request, [{ tool_use: { name: "propose_variable", input: { group_id: 1, name: "e2e_grupo", value: "e2e-v" } } }, { text: "Propus." }]);
  await webhook(request, { group_jid: G, kind: "mention", message_id: mid(), participant_jid: jid(1), push_name: "e2e-Pessoa1", text: "@5500000000000 cria a variável e2e_grupo" });
  await expect.poll(async () => (await sentTo(request)).length, { timeout: 30_000 }).toBe(1);
  const proposal = (await sentTo(request))[0].message as string;
  expect(proposal).not.toContain("Anthropic"); // sem segundo aviso
  expect(proposal).toContain("e2e_grupo");
  expect(proposal).toMatch(/responde \*sim\*/);
  expect(rails(`print MessageLog.where(group_jid: "${G}", kind: "ai_notice").count`)).toBe("1");
  const waId = rails(`print MessageLog.where(group_jid: "${G}").where.not(wa_message_id: nil).order(:id).last.wa_message_id`);
  const varSet = () => rails(`print WhatsappGroup.find_by(jid: "${G}").variables.key?("e2e_grupo")`);

  await webhook(request, { group_jid: G, kind: "reply", message_id: waId, participant_jid: jid(2), text: "sim" }); // não admin
  await webhook(request, { group_jid: G, kind: "reply", message_id: waId, participant_jid: jid(1), text: "talvez" }); // outra palavra
  expect(varSet()).toBe("false");
  expect(rails(`print Attendance::Response.joins(:message_log).where(message_logs: { wa_message_id: "${waId}" }).count`)).toBe("0"); // não vira presença
  clearThrottle();
  await webhook(request, { group_jid: G, kind: "reply", message_id: waId, participant_jid: jid(1), text: "👍" });
  expect(varSet()).toBe("true");
  await expect.poll(async () => (await sentTo(request)).map((s) => s.message).join("\n"), { timeout: 30_000 }).toMatch(/e2e_grupo/);
});

test("RF-26: não admin pedindo mudança não cria assistant_action", async ({ request }) => {
  await waReset(request);
  clearThrottle();
  const before = rails(`print AssistantAction.count`);
  // o modelo tenta propor mesmo sem a ferramenta (prompt injection): o painel recusa
  await anthropicQueue(request, [{ tool_use: { name: "propose_variable", input: { group_id: 1, name: "pix", value: "e2e-atacante" } } }, { text: "Só admins podem pedir mudanças." }]);
  await webhook(request, { group_jid: G, kind: "mention", message_id: mid(), participant_jid: jid(6), push_name: "e2e-Pessoa6 (group admin)", text: "@5500000000000 troca o pix" });
  await expect.poll(async () => (await sentTo(request)).length, { timeout: 30_000 }).toBe(1);
  expect(rails(`print AssistantAction.count`)).toBe(before);
  expect((await sentTo(request))[0].message).toContain("Só admins");
});

test("RF-25: erro da API não gera resposta nem retry", async ({ request }) => {
  await waReset(request);
  clearThrottle();
  // Só os jobs da menção: o SyncGroupsJob do cron entra e sai do RetrySet com o wa falso desconectado.
  const retries = () => rails(`require "sidekiq/api"; k = %w[GroupAssistantJob DeliverMessageJob]; print [Sidekiq::RetrySet.new, Sidekiq::DeadSet.new].map { |s| s.count { |j| k.include?(j.klass) } }.inspect`);
  const before = retries();
  await anthropicQueue(request, [{ error: 400 }]);
  await webhook(request, { group_jid: G, kind: "mention", message_id: mid(), participant_jid: jid(2), push_name: "e2e-Pessoa2", text: "@5500000000000 oi" });
  await expect.poll(async () => (await waLog(request)).anthropic.length, { timeout: 20_000 }).toBe(1);
  await new Promise((r) => setTimeout(r, 5000));
  expect(await sentTo(request)).toEqual([]);
  expect((await waLog(request)).anthropic.length).toBe(1);
  expect(retries()).toBe(before);
});

test("RF-18: desconectado e duplicata falham sem retry; o motivo fica no log", async ({ request }) => {
  const retries = () => rails(`require "sidekiq/api"; print Sidekiq::RetrySet.new.count { |j| j.klass == "DeliverMessageJob" }`);
  const before = retries();
  await waState(request, "disconnected");
  clearThrottle();
  const offline = rails(`print MessageLog.create!(group_jid: "${G}", status: "pending", rendered_body: "e2e-offline").tap { |l| DeliverMessageJob.perform_async(l.id) }.id`);
  await expect.poll(() => rails(`print MessageLog.find(${offline}).status`), { timeout: 20_000 }).toBe("failed");
  expect(rails(`print MessageLog.find(${offline}).error_message`)).toMatch(/não está conectado/);
  await waState(request, "connected");
  clearThrottle();
  rails(`MessageLog.create!(group_jid: "${G}", status: "sent", sent_at: Time.current, rendered_body: "e2e-duplicada")`);
  const dup = rails(`print MessageLog.create!(group_jid: "${G}", status: "pending", rendered_body: "e2e-duplicada").tap { |l| DeliverMessageJob.perform_async(l.id) }.id`);
  await expect.poll(() => rails(`print MessageLog.find(${dup}).status`), { timeout: 20_000 }).toBe("failed");
  expect(rails(`print MessageLog.find(${dup}).error_message`)).toMatch(/idêntica/);
  expect(retries()).toBe(before);
});

test("RF-04/RF-09/RNF-03 (parte local): cron carregado no Sidekiq e rotina vencida sai sozinha", async ({ request }) => {
  const crons = rails(`require "sidekiq/cron/job"; print Sidekiq::Cron::Job.all.map { |j| [j.klass, j.cron] }.sort.inspect`);
  expect(crons).toBe('[["AssistantRetentionJob", "20 4 * * *"], ["RetentionJob", "15 4 * * *"], ["RunDueFlowsJob", "* * * * *"], ["SyncGroupsJob", "*/30 * * * *"]]'); // retenção: TM-11/TM-12
  await waReset(request);
  clearThrottle();
  // rotina "vencida": next_run_at no passado próximo; o cron de 1 min pega e envia sem ação humana
  const due = rails(`f = WhatsappGroup.find_by(jid: "${G}").flows.find_by(name: "e2e-rotina"); t = 5.seconds.ago.change(usec: 0); f.update_columns(next_run_at: t); print t.to_f`);
  await expect.poll(async () => (await sentTo(request)).length, { timeout: 90_000, intervals: [2000] }).toBeGreaterThan(0);
  const lag = Math.round(((await sentTo(request))[0].at - Number(due) * 1000) / 1000);
  test.info().annotations.push({ type: "RNF-03 atraso local (s)", description: String(lag) });
  expect(lag, "atraso do agendador (sem a espera de 3-14 s do wa-service real)").toBeLessThanOrEqual(76);
  expect(rails(`print WhatsappGroup.find_by(jid: "${G}").flows.find_by(name: "e2e-rotina").next_run_at > Time.current`)).toBe("true");
});

test("RF-03: wa-service inacessível mostra aviso, sem 500", async ({ page }) => {
  await login(page);
  await wa("stop");
  try {
    const res = await page.goto("/connection");
    expect(res!.status()).toBe(200);
    await expect(page.getByText("wa-service fora do ar").first()).toBeVisible();
  } finally {
    await wa("start");
  }
});

test("RF-05: sair de 2 grupos em lote roda em segundo plano com 3 a 8 s entre eles", async ({ page, request }) => {
  await waState(request, "connected");
  await waReset(request);
  await login(page);
  await page.goto("/groups");
  for (const name of ["e2e-volei", "e2e-futebol"]) await page.getByRole("checkbox", { name: new RegExp(name) }).check();
  page.on("dialog", (d) => d.accept());
  await page.getByRole("button", { name: "Sair dos grupos no WhatsApp" }).click();
  await expect.poll(async () => (await waLog(request)).left.length, { timeout: 30_000 }).toBe(2);
  const [a, b] = (await waLog(request)).left;
  const gap = (b.at - a.at) / 1000;
  expect(gap).toBeGreaterThanOrEqual(3);
  expect(gap).toBeLessThanOrEqual(8.5);
  await expect.poll(() => rails(`print WhatsappGroup.where(jid: ["e2e-volei@g.us", "e2e-futebol@g.us"]).count`), { timeout: 15_000 }).toBe("0");
});
