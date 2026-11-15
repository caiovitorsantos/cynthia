// G8 / TT-01 a TT-13: os 12 eventos do tracking-plan disparam pelos caminhos reais do produto (painel, webhook do
// wa-service, Sidekiq) e gravam só IDs, códigos e contagens. Grupo e2e-futebol (o whatsapp.spec usa o e2e-volei).
// O lado do wa-service de sessao_conectada/sessao_caiu (Baileys) fica no whatsapp.test.ts; aqui, o contrato do webhook.
import { test, expect } from "@playwright/test";
import { login, groupId, webhook, waReset, waState } from "./support/helpers";
import { rails, clearThrottle } from "./support/stack";

const G = "e2e-futebol@g.us";
const jid = (n: number) => `55000000000${String(n).padStart(2, "0")}@s.whatsapp.net`; // e2e-futebol: pessoas 7 a 12, 7 é admin
let start = 0;
let msg = 0;
const mid = () => `e2e-tt-${Date.now()}-${msg++}`;
const events = (name: string): any[] =>
  JSON.parse(rails(`print AnalyticsEvent.where("id > ?", ${start}).where(name: "${name}").order(:id).map(&:properties).to_json`));

test.describe.configure({ mode: "serial" });

test.beforeAll(async ({ request }) => {
  start = Number(rails(`print AnalyticsEvent.maximum(:id).to_i`));
  await waReset(request);
  await waState(request, "connected");
  clearThrottle();
});

test("TT-02/03/05/08: rotina que abre rodada e cobrança grava fluxo_executado, cobranca_aberta, mensagem_enviada e rodada_aberta", async () => {
  // Rotina vencida rodada pelo RunDueFlowsJob (o cron de 1 min em si é coberto no whatsapp.spec).
  const due = rails(`g = WhatsappGroup.find_by(jid: "${G}"); t = g.templates.find_by(name: "e2e-lista")
    f = g.flows.create!(name: "e2e-tt-rotina", trigger: "schedule", cron_expression: "0 9 * * 1", timezone: "America/Sao_Paulo",
      steps: [{ "type" => "send_message", "template_id" => t.id.to_s, "opens_round" => "1", "opens_billing" => "1" }])
    f.update_columns(next_run_at: 1.minute.ago.change(usec: 0)); RunDueFlowsJob.new.perform; print f.id`);
  await expect.poll(() => events("rodada_aberta").length, { timeout: 30_000 }).toBe(1);
  const [run] = events("fluxo_executado");
  expect(run).toMatchObject({ flow_id: Number(due), origem: "rotina", passos: 1 });
  expect(run.agendado_para, "agendado_para = next_run_at anterior").toBeTruthy();
  expect(events("cobranca_aberta")[0]).toMatchObject({ mensalidades: 3, diarias: 0 });
  expect(events("cobranca_aberta")[0].periodo).toMatch(/^\d{4}-\d{2}$/);
  expect(events("mensagem_enviada")[0]).toMatchObject({ origem: "rotina", abre_rodada: true, abre_cobranca: true, tentativa: 1 });
  expect(events("rodada_aberta")[0].membros_cobrados).toBe(3);
});

test("TT-06/07: reação na rodada grava presenca_registrada e remover grava presenca_desfeita", async ({ request }) => {
  const round = rails(`print MessageLog.where(group_jid: "${G}", opens_round: true, status: "sent").order(:id).last.wa_message_id`);
  await webhook(request, { group_jid: G, kind: "reaction", message_id: round, participant_jid: jid(8), text: "✅" });
  await webhook(request, { group_jid: G, kind: "reaction", message_id: round, participant_jid: jid(8), text: "" });
  expect(events("presenca_registrada")).toEqual([expect.objectContaining({ origem: "reacao", status: "confirmed", convidado: false, membro_cobrado: true, alterou_resposta: false })]);
  expect(events("presenca_desfeita")).toHaveLength(1);
});

test("TT-01/09/10: login grava admin_logado; marcar e desfazer pago no painel gravam cobranca_paga e cobranca_desmarcada", async ({ page }) => {
  await login(page);
  expect(events("admin_logado")).toEqual([{}]);
  await page.goto(`/groups/${await groupId(page, "e2e-futebol")}?tab=regras#regras`);
  await page.getByRole("button", { name: "Marcar pago" }).first().click();
  await page.getByRole("button", { name: "Desfazer" }).first().click();
  await expect.poll(() => events("cobranca_desmarcada").length).toBe(1);
  expect(events("cobranca_paga")).toEqual([expect.objectContaining({ tipo: "mensal", origem: "painel" })]);
});

test("TT-02/03/04: comando grava fluxo_executado (comando); desconectado grava mensagem_falhou sem retry", async ({ request }) => {
  clearThrottle();
  await webhook(request, { group_jid: G, kind: "command", message_id: mid(), participant_jid: jid(9), push_name: "e2e-Pessoa9", text: `!espera e2e-tt-${Date.now()}` });
  await expect.poll(() => events("mensagem_enviada").filter((e) => e.origem === "comando").length, { timeout: 30_000 }).toBe(1);
  expect(events("fluxo_executado").map((e) => e.origem)).toContain("comando");

  await waState(request, "disconnected");
  clearThrottle();
  await webhook(request, { group_jid: G, kind: "command", message_id: mid(), participant_jid: jid(9), push_name: "e2e-Pessoa9", text: `!espera e2e-tt-off-${Date.now()}` });
  await expect.poll(() => events("mensagem_falhou").length, { timeout: 30_000 }).toBe(1);
  expect(events("mensagem_falhou")[0]).toMatchObject({ motivo: "desconectado", vai_retentar: false, origem: "comando" });
  await waState(request, "connected");
});

test("TT-11/12: eventos de sessão do wa-service entram pelo webhook autenticado; nome fora da lista é 422", async ({ request }) => {
  expect((await webhook(request, { kind: "session", event: "sessao_caiu", codigo: 428, logout: false })).status()).toBe(204);
  expect((await webhook(request, { kind: "session", event: "sessao_conectada", apos_queda_s: 3 })).status()).toBe(204);
  expect((await webhook(request, { kind: "session", event: "e2e-outro" })).status()).toBe(422);
  expect((await webhook(request, { kind: "session", event: "sessao_caiu", codigo: 1 }, "e2e-token-errado")).status()).toBe(401);
  expect(events("sessao_caiu")).toEqual([{ codigo: 428, logout: false }]);
  expect(events("sessao_conectada")).toEqual([{ apos_queda_s: 3 }]);
});

test("TT-13: os 12 eventos dispararam e nenhuma propriedade tem telefone, JID, nome ou texto", async () => {
  const names = JSON.parse(rails(`print AnalyticsEvent.where("id > ?", ${start}).distinct.pluck(:name).sort.to_json`));
  expect(names).toEqual(["admin_logado", "cobranca_aberta", "cobranca_desmarcada", "cobranca_paga", "fluxo_executado", "mensagem_enviada",
    "mensagem_falhou", "presenca_desfeita", "presenca_registrada", "rodada_aberta", "sessao_caiu", "sessao_conectada"]);
  const props = rails(`print AnalyticsEvent.where("id > ?", ${start}).pluck(:properties).to_json`);
  expect(props.match(/\d{8,}|@|e2e-|Pessoa|whatsapp\.net|g\.us/g) ?? []).toEqual([]);
});
