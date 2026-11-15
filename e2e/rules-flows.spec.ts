// Critérios do PRD que as suítes unitárias não cobriam (test-plan TC-04, TC-08, TC-11, TC-13, TC-14).
import { test, expect } from "@playwright/test";
import { login, groupId, waReset, waLog, waState, webhook } from "./support/helpers";
import { rails, clearThrottle } from "./support/stack";

test.describe.configure({ mode: "serial" });

test("RF-04: grupos com fluxos ou regras aparecem antes dos sem automação", async ({ page }) => {
  rails(`WhatsappGroup.find_or_create_by!(jid: "e2e-aaa@g.us") { |g| g.name = "e2e-aaa-sem-fluxo" }`);
  await login(page);
  await page.goto("/groups");
  const names = (await page.locator("tbody tr td:nth-child(2) a").allTextContents()).map((s) => s.trim()).filter((s) => s.startsWith("e2e-"));
  expect(names.indexOf("e2e-aaa-sem-fluxo")).toBeGreaterThan(Math.max(names.indexOf("e2e-volei"), names.indexOf("e2e-futebol")));
});

test("RF-11: recusa fluxo sem passos, template de outro grupo e variável sem fonte", async ({ page }) => {
  await login(page);
  const id = await groupId(page, "e2e-volei");
  const errors = page.locator("form .bg-red-950\\/50");

  await page.goto(`/groups/${id}/flows/new?trigger=schedule`);
  await page.getByLabel("Nome").first().fill("e2e-sem-passos");
  await page.getByRole("button", { name: "Salvar fluxo" }).click();
  await expect(errors).toBeVisible();

  // template de outro grupo: injeta o id de um template do e2e-futebol no select
  const other = rails(`print WhatsappGroup.find_by(jid: "e2e-futebol@g.us").templates.first.id`);
  await page.goto(`/groups/${id}/flows/new?trigger=schedule`);
  await page.getByLabel("Nome").first().fill("e2e-outro-grupo");
  await page.locator("select[name*='[type]']").first().selectOption("send_message");
  await page.locator("select[name*='[template_id]']").first().evaluate((el: HTMLSelectElement, v) => { el.add(new Option("e2e-outro", v)); el.value = v; }, other);
  await page.getByRole("button", { name: "Salvar fluxo" }).click();
  await expect(errors).toBeVisible();

  // template com variável que nenhuma fonte fornece
  const tpl = rails(`print WhatsappGroup.find(${id}).templates.find_or_create_by!(name: "e2e-sem-fonte") { |t| t.body = "Oi {{e2e_nada}}" }.id`);
  await page.goto(`/groups/${id}/flows/new?trigger=schedule`);
  await page.getByLabel("Nome").first().fill("e2e-sem-fonte");
  await page.locator("select[name*='[type]']").first().selectOption("send_message");
  await page.locator("select[name*='[template_id]']").first().selectOption(tpl);
  await page.getByRole("button", { name: "Salvar fluxo" }).click();
  await expect(errors).toContainText("e2e_nada");
  expect(rails(`print Flow.where(name: %w[e2e-sem-passos e2e-outro-grupo e2e-sem-fonte]).count`)).toBe("0");
});

test("RF-08: {{data}} usa o fuso do fluxo", async ({ page, request }) => {
  const zone = "Pacific/Kiritimati"; // UTC+14: data diferente de São Paulo na maior parte do dia
  const flow = rails(`g = WhatsappGroup.find_by(jid: "e2e-volei@g.us"); t = g.templates.find_or_create_by!(name: "e2e-data") { |x| x.body = "e2e-data {{data}}" }; ` +
    `print g.flows.create!(name: "e2e-fuso", trigger: "schedule", cron_expression: "0 9 * * 1", timezone: "${zone}", steps: [{ "type" => "send_message", "template_id" => t.id.to_s }]).id`);
  await waState(request, "connected");
  await waReset(request);
  clearThrottle();
  rails(`RunFlowJob.perform_async(${flow})`);
  await expect.poll(async () => (await waLog(request)).sent.length, { timeout: 30_000 }).toBeGreaterThan(0);
  const expected = new Intl.DateTimeFormat("pt-BR", { timeZone: zone, day: "2-digit", month: "2-digit" }).format(new Date());
  expect((await waLog(request)).sent[0].message).toContain(expected);
  rails(`Flow.find(${flow}).destroy`);
});

test("RF-13/RF-14: checklist da regra e lista colada com cabeçalho sem acento e em minúsculas", async ({ page, request }) => {
  await login(page);
  await page.goto(`/groups/${await groupId(page, "e2e-volei")}#regras`);
  const checklist = page.locator("#regras ol").first();
  await expect(checklist).toContainText("✅"); // listas cobradas configuradas
  await expect(checklist).toContainText("⚠️"); // falta rotina que abre rodada
  rails(`MessageLog.create!(group_jid: "e2e-volei@g.us", status: "sent", sent_at: Time.current, opens_round: true, wa_message_id: "e2e-round-lista", rendered_body: "*PRESENÇA 21/10*\\n1. e2e-Pessoa1\\n2. e2e-Pessoa2")`);
  await webhook(request, { group_jid: "e2e-volei@g.us", kind: "list", message_id: "e2e-cola-1", participant_jid: "5500000000002@s.whatsapp.net", text: "presenca 21/10\n1. e2e-Pessoa1\n2. e2e-pessoa2 ✅" });
  expect(rails(`print Attendance::Response.where(message_log: MessageLog.find_by(wa_message_id: "e2e-round-lista")).joins(:group_participant).pluck("group_participants.name", :status).inspect`))
    .toBe('[["e2e-Pessoa2", "confirmed"]]');
});
