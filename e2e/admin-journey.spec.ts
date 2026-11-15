// E2E-01: jornada do admin. Um login, passos em sequência (test-plan, TC-01e).
import { test, expect } from "@playwright/test";
import { env, login, waState, waLog, waReset, axe } from "./support/helpers";
import { clearThrottle, rails } from "./support/stack";

test("E2E-01 jornada do admin", async ({ page, request }) => {
  let listKey = "e2e_lista";
  let tabAfterSave = "";
  const errors: string[] = [];
  page.on("console", (m) => m.type() === "error" && !m.text().startsWith("Failed to load resource") && errors.push(`console: ${m.text()}`)); // recursos: pela rede abaixo
  page.on("response", (r) => r.status() >= 400 && !(r.status() === 422 && r.url().endsWith("/login")) && errors.push(`${r.status()} ${r.url()}`));
  page.on("dialog", (d) => d.accept()); // turbo_confirm usa o confirm nativo
  await waReset(request);
  await waState(request, "qr_pending");

  await test.step("1. / sem sessão: 200 e link para /login (RF-02)", async () => {
    const res = await page.goto("/");
    expect(res!.status()).toBe(200);
    await expect(page.locator('a[href="/login"]').first()).toBeVisible();
  });

  await test.step("2. sem sessão vai para /login; senha errada 422 com alerta; certa leva a /groups (RF-01)", async () => {
    await page.goto("/groups");
    await expect(page).toHaveURL(/\/login$/);
    await page.getByLabel(/usuário/i).fill(env.ADMIN_USERNAME);
    await page.getByLabel(/senha/i).fill("e2e-errada");
    const [res] = await Promise.all([page.waitForResponse((r) => r.url().endsWith("/login") && r.request().method() === "POST"), page.getByRole("button", { name: "Entrar" }).click()]);
    expect(res.status()).toBe(422);
    await expect(page.getByRole("status").first()).toBeVisible();
    await login(page);
  });

  await test.step("3. modal da conta: QR em qr_pending, conectado em connected, desconectar volta ao QR (RF-03)", async () => {
    await page.getByRole("button", { name: env.ADMIN_USERNAME }).click();
    const dialog = page.getByRole("dialog", { name: /conta/i }).or(page.locator("dialog[open]"));
    await expect(dialog.getByRole("img", { name: "QR Code" })).toBeVisible();
    await axe(page, "modal da conta");
    await waState(request, "connected");
    await expect(dialog.getByText("conectado", { exact: true })).toBeVisible({ timeout: 12_000 }); // poller de 5 s
    await dialog.getByRole("button", { name: "Desconectar este número" }).click();
    await expect(page.locator("dialog[open]").getByRole("img", { name: "QR Code" }).or(page.getByRole("img", { name: "QR Code" }))).toBeVisible();
    expect((await (await request.get("http://127.0.0.1:" + (process.env.E2E_WA_PORT ?? 3556) + "/health")).json()).status).toBe("qr_pending");
    await page.keyboard.press("Escape"); // Esc fecha o modal (RNF-04)
    await expect(page.locator("dialog[open]")).toHaveCount(0);
  });

  await test.step("4. sincronizar: desconectado mostra alerta; conectado sincroniza (RF-04)", async () => {
    await page.goto("/groups");
    await page.getByRole("button", { name: "Sincronizar agora" }).click();
    await expect(page.getByText(/não está conectado/i)).toBeVisible();
    await waState(request, "connected");
    await page.getByRole("button", { name: "Sincronizar agora" }).click();
    await expect(page.getByRole("link", { name: "e2e-volei", exact: true })).toBeVisible();
  });

  await test.step("5. lista e2e-lista com chave e2e_lista e 2 membros (RF-06)", async () => {
    await page.getByRole("link", { name: "e2e-volei", exact: true }).click();
    const manage = page.locator("#membros details > summary");
    await manage.click();
    await page.getByPlaceholder("nova lista").fill("e2e-lista");
    await page.getByRole("button", { name: "Salvar listas" }).click();
    await manage.click();
    // A chave vem do nome; ela precisa caber em {{lista:chave}} (Template::VARIABLE_PATTERN usa \w).
    const keyCell = page.locator("#membros details tr", { has: page.locator('input[value="e2e-lista"]') }).locator("td").nth(1);
    listKey = ((await keyCell.textContent()) ?? "").trim();
    expect.soft(listKey, "chave da lista e2e-lista utilizável em template").toMatch(/^\w+$/);
    const rows = page.locator("#membros tbody tr");
    for (const i of [0, 1]) await rows.nth(i).getByRole("checkbox", { name: "e2e-lista" }).check();
    await page.getByRole("button", { name: "Salvar membros" }).click();
    await expect(page.locator("#membros").getByRole("button", { name: /e2e-lista\s*2/ })).toBeVisible();
  });

  await test.step("6. template com formatação: a prévia formata (RF-08)", async () => {
    await page.getByRole("tab", { name: /templates/i }).click();
    await page.getByRole("link", { name: "Novo template" }).click();
    await page.getByLabel(/nome/i).first().fill("e2e-formatado");
    await page.getByLabel(/texto|corpo|mensagem/i).first().fill(`*negrito* _itálico_ ~riscado~ {{lista:${listKey}}}`);
    const bubble = page.locator("[data-template-preview-target=bubble]");
    await expect(bubble.locator("strong")).toHaveText("negrito");
    await expect(bubble.locator("em")).toHaveText("itálico");
    await expect(bubble.locator("del")).toHaveText("riscado");
    await axe(page, "formulário de template");
    await page.getByRole("button", { name: "Salvar template" }).click();
    await page.getByRole("tab", { name: /templates/i }).click();
    await expect(page.getByRole("link", { name: "e2e-formatado" }).first()).toBeVisible();
  });

  await test.step("7. rotina toda terça 14:00: por extenso e próximos envios (RF-09)", async () => {
    await page.getByRole("tab", { name: /fluxos/i }).click();
    await page.getByRole("link", { name: "Nova rotina" }).click();
    await page.getByLabel("Nome", { exact: false }).first().fill("e2e-terca");
    await page.locator("#schedule_mode").selectOption("custom");
    await page.getByLabel(/cron/i).fill("0 14 * * 2");
    await page.getByRole("button", { name: "Ver próximos envios" }).click();
    const preview = page.locator("turbo-frame#cron_preview_frame");
    await expect(preview).toContainText(/\d{2}\/\d{2}\/\d{4} 14:00/);
    const dates = [...((await preview.textContent()) ?? "").matchAll(/(\d{2})\/(\d{2})\/(\d{4}) 14:00/g)];
    expect(dates.length).toBeGreaterThanOrEqual(3);
    for (const [, d, m, y] of dates) expect(new Date(Date.UTC(+y, +m - 1, +d)).getUTCDay(), "próximo envio é terça").toBe(2);
    await axe(page, "formulário de fluxo (rotina)");
    await page.locator("select[name*='[type]']").first().selectOption("send_message");
    await page.locator("select[name*='[template_id]']").first().selectOption({ label: "e2e-formatado" });
    await page.getByRole("button", { name: "Salvar fluxo" }).click();
    tabAfterSave = (await page.getByRole("tab", { selected: true }).textContent())?.trim() ?? "";
    await page.getByRole("tab", { name: /fluxos/i }).click();
    await expect(page.locator("#fluxos tr", { hasText: "e2e-terca" })).toContainText(/terça às 14:00/i);
  });

  await test.step("8. Executar agora: o envio chega ao wa e aparece em /logs (RF-12, RF-17)", async () => {
    clearThrottle();
    const row = page.locator("#fluxos tr", { hasText: "e2e-terca" });
    await row.getByRole("button", { name: "Executar agora" }).click();
    await expect.poll(async () => (await waLog(request)).sent.map((s) => s.message).join("\n"), { timeout: 30_000 }).toContain("negrito");
    const sent = (await waLog(request)).sent.at(-1);
    expect(sent.group_jid).toBe("e2e-volei@g.us");
    // {{lista:<chave>}} renderiza os 2 membros marcados (RF-06/RF-08)
    expect.soft(sent.message, "lista renderizada no envio").toMatch(/e2e-Pessoa1[\s\S]*e2e-Pessoa2/);
    expect.soft(sent.message, "variável não resolvida no envio").not.toContain("{{");
    await page.getByRole("link", { name: /logs/i }).first().click();
    const first = page.locator("tbody tr").first();
    await expect(first).toContainText("negrito");
    await expect(first).toContainText(/enviad/i);
  });

  await test.step("9. /logs: 25 por página, filtro por status e reenvio bloqueado mostra o motivo (RF-17, RF-18)", async () => {
    await expect(page.locator("tbody tr")).toHaveCount(25);
    await page.locator("select[name=status]").selectOption("failed");
    await expect(page).toHaveURL(/status=failed/);
    const statuses = await page.locator("tbody tr td:nth-child(3)").allInnerTexts();
    expect(statuses.every((s) => /falhou/i.test(s))).toBe(true);
    await axe(page, "/logs filtrado");
    // Último envio foi há menos de 20 s: o SendGuard bloqueia e o painel mostra o motivo.
    const logs = rails("print MessageLog.count");
    await page.locator("tbody tr").first().getByRole("button", { name: "Reenviar" }).click();
    await expect.poll(() => rails("print MessageLog.count")).toBe(String(Number(logs) + 1)); // reenvio cria log novo
    await expect(page.getByRole("status").filter({ hasText: /20\s?s|aguardando|janela/i })).toBeVisible();
  });

  await test.step("10. idioma es no cabeçalho e logout (RF-20, RF-01)", async () => {
    await page.getByRole("button", { name: env.ADMIN_USERNAME }).click();
    await page.locator("dialog[open]").getByRole("button", { name: "ES" }).click();
    await expect(page.locator("html")).toHaveAttribute("lang", "es");
    await expect(page.getByRole("link", { name: /grupos/i }).first()).toBeVisible();
    await page.getByRole("button", { name: env.ADMIN_USERNAME }).click();
    await page.locator("dialog[open]").getByRole("button", { name: "Salir del panel" }).click();
    await page.waitForURL(/\/login$/);
    await page.goto("/groups");
    await expect(page).toHaveURL(/\/login$/);
    // volta para pt-BR para os próximos specs
    await page.getByRole("button", { name: "PT" }).click();
  });

  test.info().annotations.push({ type: "aba depois de salvar fluxo (redirect com #fluxos)", description: tabAfterSave });
  expect.soft(errors, "console e rede (só erros e 4xx/5xx inesperados)").toEqual([]);
});
